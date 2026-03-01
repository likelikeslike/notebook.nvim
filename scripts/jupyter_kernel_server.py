import json
import queue
import signal
import sys
import threading

from jupyter_client import KernelManager

km = None
kc = None
interrupt_flag = threading.Event()
output_lock = threading.Lock()


def handle_signal(signum, frame):
    global km
    if km:
        km.shutdown_kernel()
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)


def respond(data):
    with output_lock:
        print(json.dumps(data), flush=True)


def start_kernel(kernel_name):
    global km, kc
    km = KernelManager(kernel_name=kernel_name)
    km.start_kernel()
    kc = km.client()
    kc.start_channels()
    kc.wait_for_ready(timeout=60)
    respond({"status": "ready", "connection_file": km.connection_file})


def execute_code(code):
    global kc, interrupt_flag
    interrupt_flag.clear()
    was_interrupted = False
    msg_id = kc.execute(code)

    while True:
        try:
            msg = kc.get_iopub_msg(timeout=0.5)
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            msg_type = msg["header"]["msg_type"]
            content = msg["content"]

            if msg_type == "execute_input":
                respond(
                    {
                        "type": "execute_count",
                        "execution_count": content.get("execution_count"),
                    }
                )
            elif msg_type == "stream":
                respond(
                    {
                        "type": "output",
                        "output": {
                            "output_type": "stream",
                            "name": content.get("name", "stdout"),
                            "text": content.get("text", ""),
                        },
                    }
                )
            elif msg_type == "execute_result":
                respond(
                    {
                        "type": "output",
                        "output": {
                            "output_type": "execute_result",
                            "data": content.get("data", {}),
                            "execution_count": content.get("execution_count"),
                        },
                    }
                )
            elif msg_type == "display_data":
                respond(
                    {
                        "type": "output",
                        "output": {
                            "output_type": "display_data",
                            "data": content.get("data", {}),
                        },
                    }
                )
            elif msg_type == "error":
                if content.get("ename") == "KeyboardInterrupt":
                    was_interrupted = True
                respond(
                    {
                        "type": "output",
                        "output": {
                            "output_type": "error",
                            "ename": content.get("ename", ""),
                            "evalue": content.get("evalue", ""),
                            "traceback": content.get("traceback", []),
                        },
                    }
                )
            elif msg_type == "status" and content.get("execution_state") == "idle":
                break
        except queue.Empty:
            if interrupt_flag.is_set():
                was_interrupted = True
            continue
        except Exception as e:
            respond(
                {
                    "type": "output",
                    "output": {
                        "output_type": "error",
                        "ename": "KernelError",
                        "evalue": str(e),
                        "traceback": [],
                    },
                }
            )
            break

    execution_count = None
    try:
        reply = kc.get_shell_msg(timeout=2)
        if reply and reply.get("content"):
            execution_count = reply["content"].get("execution_count")
    except Exception:
        pass

    respond(
        {
            "type": "done",
            "interrupted": was_interrupted,
            "execution_count": execution_count,
        }
    )


def get_variables():
    code = """
import json as __nb_json__
__nb_vars__ = {}
for __nb_name__ in dir():
    if not __nb_name__.startswith('_'):
        try:
            __nb_val__ = eval(__nb_name__)
            __nb_vars__[__nb_name__] = {'type': type(__nb_val__).__name__, 'value': repr(__nb_val__)[:100]}
        except: pass
print("__VARS__" + __nb_json__.dumps(__nb_vars__) + "__VARS__")
del __nb_json__, __nb_vars__, __nb_name__, __nb_val__
"""
    global kc
    msg_id = kc.execute(code)

    while True:
        try:
            msg = kc.get_iopub_msg(timeout=10)
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            if msg["header"]["msg_type"] == "stream":
                text = msg["content"].get("text", "")
                if "__VARS__" in text:
                    start = text.find("__VARS__") + 8
                    end = text.rfind("__VARS__")
                    respond({"variables": json.loads(text[start:end])})
                    return
            elif (
                msg["header"]["msg_type"] == "status"
                and msg["content"].get("execution_state") == "idle"
            ):
                break
        except:
            break
    respond({"variables": {}})


def inspect_var(name):
    code = f"""
try:
    __nb_v__ = {name}
    print("__INFO__" + type(__nb_v__).__name__ + "\\n" + repr(__nb_v__) + "__INFO__")
except Exception as e:
    print("__INFO__Error: " + str(e) + "__INFO__")
finally:
    try: del __nb_v__
    except NameError: pass
"""
    global kc
    msg_id = kc.execute(code)

    while True:
        try:
            msg = kc.get_iopub_msg(timeout=5)
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            if msg["header"]["msg_type"] == "stream":
                text = msg["content"].get("text", "")
                if "__INFO__" in text:
                    start = text.find("__INFO__") + 8
                    end = text.rfind("__INFO__")
                    respond({"info": text[start:end]})
                    return
            elif (
                msg["header"]["msg_type"] == "status"
                and msg["content"].get("execution_state") == "idle"
            ):
                break
        except:
            break
    respond({"info": "No info"})


executing = threading.Event()
execute_thread = None


def interrupt():
    global km, interrupt_flag
    interrupt_flag.set()
    if km:
        km.interrupt_kernel()


def restart():
    global km, kc
    if km:
        km.restart_kernel()
        kc = km.client()
        kc.start_channels()
        kc.wait_for_ready(timeout=60)
    respond({"status": "restarted"})


def run_execute(code):
    global executing
    try:
        execute_code(code)
    finally:
        executing.clear()


for line in sys.stdin:
    try:
        cmd = json.loads(line.strip())
        action = cmd.get("action")

        if action == "start":
            start_kernel(cmd.get("kernel", "python3"))
        elif action == "execute":
            if executing.is_set():
                respond({"type": "done", "interrupted": True})
            else:
                executing.set()
                execute_thread = threading.Thread(
                    target=run_execute, args=(cmd.get("code", ""),)
                )
                execute_thread.start()
        elif action == "variables":
            get_variables()
        elif action == "inspect":
            inspect_var(cmd.get("name", ""))
        elif action == "interrupt":
            interrupt()
        elif action == "restart":
            if execute_thread and execute_thread.is_alive():
                interrupt_flag.set()
                execute_thread.join(timeout=2)
            restart()
        elif action == "shutdown":
            if km:
                km.shutdown_kernel()
            respond({"status": "shutdown"})
            break
    except Exception as e:
        respond({"error": str(e)})
