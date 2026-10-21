# CPU model server (HP)

The HP can serve a language model over an OpenAI-compatible API with llama.cpp's `llama-server`. It runs on the CPU only, so it suits Mixture-of-Experts (MoE) models. Those models store many parameters but use only a few billion for each token, and that is what an older server CPU can keep up with.

This is a separate install from the web app. It is written for the **current** HP: Ubuntu Server 26.04.1, models on `/srv/models`, one Xeon E5-2620. Nothing here has run on the real HP yet. The speed figures below are estimates, not measurements.

## What you get

| Item | Value |
| --- | --- |
| Service | `llama-server.service`, run by the unprivileged `llama` account |
| API | `http://HP_IP:10000/v1` (OpenAI-compatible: `/v1/chat/completions`, `/v1/completions`, `/v1/models`) |
| Browser chat | `http://HP_IP:10000/` (llama.cpp's built-in page; it asks for the API key) |
| Health | `http://HP_IP:10000/health`: `200` ready, `503` still loading. No key needed. |
| Metrics | `http://HP_IP:10000/metrics` (Prometheus format, needs the key) |
| API key | `/etc/homelab/llama-server/api-keys`. Every request except `/health` needs it. |
| Settings | `/etc/homelab/llama-server.env`, created from [`hp/llm/llama-server.env.example`](../../hp/llm/llama-server.env.example) |
| Watchdog | `llama-server-health.timer` checks `/health` every two minutes. If the service has been up for 15 minutes and is still not ready, it restarts it. |
| llama.cpp | Release `v0.7.0`, pinned to commit `620d2225`. It is built on the HP for its own CPU. |

## Model choice

The HP has **28 GB of RAM today**, and Ubuntu sees about 26 GiB. Generation speed on this CPU depends on memory bandwidth, not core count. A model whose active parameters are small is fast, even when its total size is large.

| When | Model | Size on disk | Active per token | Memory limit |
| --- | --- | ---: | ---: | ---: |
| **Now (default)** | `gpt-oss-20b`, MXFP4 ([ggml-org/gpt-oss-20b-GGUF](https://huggingface.co/ggml-org/gpt-oss-20b-GGUF), file `gpt-oss-20b-mxfp4.gguf`) | about 13 GB | 3.6B | 18 GiB hard cap |
| **After the 96 GB upgrade** | `gpt-oss-120b`, MXFP4 ([ggml-org/gpt-oss-120b-GGUF](https://huggingface.co/ggml-org/gpt-oss-120b-GGUF), three `gpt-oss-120b-mxfp4-0000N-of-00003.gguf` parts) | about 63 GB | 5.1B | 80 GiB hard cap |

The 18 GiB cap leaves about 8 GiB for Ubuntu, Samba and the always-on services stack, which budgets about 6 GiB. Both models use the same chat format and tool-calling support, so clients do not change when you upgrade.

Expected speed on one E5-2620 with four channels of DDR3: a few tokens a second for `gpt-oss-20b`, and slower for `gpt-oss-120b`. Prompt reading is slower than on a GPU, so very long prompts take a while. Measure on the real machine before you rely on these numbers.

## Settings that matter

- **Threads:** `LLAMA_ARG_THREADS=6` and `HOMELAB_LLAMA_THREADS_BATCH=6`, one per physical core. Generation waits on memory, so hyper-threads rarely help. You can try `12` for batch threads and compare prompt speed in the log.
- **NUMA:** none today; the HP has one CPU, so it has one NUMA node. If you fit a second CPU with the RAM upgrade, set `LLAMA_ARG_NUMA=distribute` and drop the page cache once before the first start. `plan` prints the node count and reminds you.
- **mmap from the array:** `LLAMA_ARG_LOAD_MODE=mmap` maps the GGUF straight from `/srv/models` on the RAID0 array. The weights live in the page cache. A service restart then reloads from RAM, not disk, and under memory pressure the kernel can drop cold pages instead of killing the process. The first load reads the whole file from the array. That takes about a minute for `gpt-oss-20b` and several minutes for `gpt-oss-120b`.
- **Memory limits:** `HOMELAB_LLAMA_MEMORY_HIGH` and `HOMELAB_LLAMA_MEMORY_MAX` become systemd `MemoryHigh` and `MemoryMax`. Above HIGH the kernel reclaims the service's pages. Answers slow down, but the service does not crash. Swap is off for the service. The installer refuses a MAX above 90% of RAM or below the model size plus 10%.
- **Context:** 32,768 tokens with one request at a time (`LLAMA_ARG_N_PARALLEL=1`). The prompt cache is held to 1 GiB (`LLAMA_ARG_CACHE_RAM=1024`).
- **Priority:** the service runs with `Nice=5` and lower CPU and I/O weight. Samba and the Steam downloads keep priority.

## Install

On the HP, from your clone of this repo:

1. **Look first.** This changes nothing:

   ```bash
   sudo bash hp/llm/install-llama-server.sh plan
   ```

   **You should see:** the CPU line (`6 physical cores, 1 NUMA node(s)`), the RAM, and either the model's size or `Model not found yet`.

2. **Put the model in place.** The installer never downloads models. The simplest way is from the Windows PC: download `gpt-oss-20b-mxfp4.gguf` from the Hugging Face page above and copy it to `M:\gpt-oss-20b\`. `M:` is the `ModelFiles` share at `/srv/models`. To download on the HP instead, run it as the account that owns `/srv/models` (shown here as `lab`). It needs the Hugging Face `hf` tool (`pipx install 'huggingface_hub[cli]'`):

   ```bash
   sudo -u lab mkdir -p /srv/models/gpt-oss-20b
   sudo -u lab hf download ggml-org/gpt-oss-20b-GGUF gpt-oss-20b-mxfp4.gguf --local-dir /srv/models/gpt-oss-20b
   ```

3. **Install.** This builds llama.cpp, which takes 10 to 20 minutes on this CPU. It creates the `llama` account, the settings file and an API key, then starts the service if the model is present:

   ```bash
   sudo bash hp/llm/install-llama-server.sh install
   ```

   If it says `The llama account cannot read ...`, run the `setfacl` command it prints, then run the install again.

4. **Verify** after the model has loaded:

   ```bash
   sudo bash hp/llm/install-llama-server.sh verify
   ```

   **You should see:** `PASS: llama-server is ready on port 10000`, `PASS: /v1/models lists gpt-oss-20b`, then `PASS: llama-server, health check and API`.

5. **Get the API key** and keep it with your other homelab secrets:

   ```bash
   sudo cat /etc/homelab/llama-server/api-keys
   ```

Re-running `install` is safe. It keeps your settings file and key, reuses the build, and rewrites only the unit files and memory limits.

## Upgrade to the larger model

After the RAM upgrade, check that Ubuntu sees it (`free -g`). Copy the three `gpt-oss-120b` parts into `/srv/models/gpt-oss-120b/`. Then, in `/etc/homelab/llama-server.env`, replace the model, alias, context and memory lines with the commented **After the 96 GB upgrade** block and run `install` again. It applies the new memory limits and restarts the service.

## Use it from the PCs

Clients need three things: the base URL `http://192.168.1.241:10000/v1` (use the HP's current address), the API key, and the model name `gpt-oss-20b` (or leave the model blank where a client allows it). Test it from a PC:

```powershell
curl.exe -H "Authorization: Bearer KEY" http://192.168.1.241:10000/v1/models
```

### From the ai-workspace dashboard

The [ai-workspace](https://github.com/Noxy-HNR/ai-workspace) dashboard on port 9090 talks only to the PC's **own** llama-server at `127.0.0.1:10000`. It has no setting for a remote server yet, so the HP does not appear in its Services or Chat tabs. What works today:

- **Relay Station (Telegram bot):** in its console at `http://127.0.0.1:9095`, open Settings, then LLM. Set *LLM base URL* to `http://192.168.1.241:10000/v1`, turn on *Allow remote model endpoint*, and paste the key into *API key*.
- **OpenCode, scripts and other OpenAI clients:** use the base URL and key above.
- **Chat in a browser:** open `http://192.168.1.241:10000/` and enter the key.

The server allows browser calls from pages served on a PC's loopback address (`LLAMA_ARG_CORS_ORIGINS=localhost`), so a dashboard page at `http://127.0.0.1:9090` can call the HP once it has an endpoint setting. Those calls still need the key. Adding that setting to the dashboard is a separate change in ai-workspace.

### Over Tailscale

The service listens on every interface, including `tailscale0`, and always needs the key. After you install Tailscale on the HP and sign it in to your tailnet, you can use either address:

- **Direct:** `http://HP_TAILNET_NAME:10000/v1`, using the HP's MagicDNS name or its `100.x.y.z` address.
- **HTTPS through Tailscale Serve** (recommended away from home, because the key then never crosses a network in plain text):

  ```bash
  sudo tailscale serve --bg --https=443 http://127.0.0.1:10000
  ```

  The base URL is then `https://HP_TAILNET_NAME.YOUR_TAILNET.ts.net/v1`. `tailscale serve status` shows it, and `sudo tailscale serve --https=443 off` removes it.

Do not use Tailscale **Funnel** for this. Funnel publishes the server to the whole internet.

To stop LAN or tailnet devices you do not trust from reaching the port at all, restrict it with a firewall. For example, with `ufw`, allow `10000/tcp` only from `192.168.1.0/24` and on `tailscale0`. Allow SSH before you enable `ufw`.

## Everyday commands

| I want to... | Run on the HP |
| --- | --- |
| See if it is ready | `bash hp/llm/llama-health.sh` |
| Read the log | `sudo journalctl -u llama-server -n 80 --no-pager` |
| Restart after editing settings | `sudo systemctl restart llama-server` (memory-limit changes need `install` again) |
| Stop it to free RAM | `sudo systemctl stop llama-server` (it starts again at boot; add `disable` to stop that) |
| Check memory use | `systemctl status llama-server` (the `Memory:` line) |

## If something goes wrong

| You see | What it means | What to do |
| --- | --- | --- |
| `Ubuntu 26.04 is required` | This is not the current HP install. | Run it on the HP. |
| `/srv/models is not mounted` | The models volume is missing. | Fix the mount first; see [HP current state](../HP-CURRENT-STATE.md). |
| `Model not found yet` | The GGUF is not at `LLAMA_ARG_MODEL`. | Copy it there, or fix the path in the settings file. |
| `The llama account cannot read ...` | The model folder belongs to `lab` only. | Run the `setfacl` command the installer prints. |
| `... larger than HOMELAB_LLAMA_MEMORY_MAX` | The model does not fit the limit. | Use the default model, or raise the limit after the RAM upgrade. |
| `/health` stays `503` for many minutes | The first read from the array is slow, or the page cache is being evicted. | Check `free -g` and the log. The watchdog restarts the service after 15 minutes. |
| `401` from a client | Missing or wrong key. | Send `Authorization: Bearer KEY` with the key from `/etc/homelab/llama-server/api-keys`. |

## Tests

```bash
python3 hp/llm/test_llama_config.py
```

These offline tests check that the settings use only names llama.cpp v0.7.0 reads, that the default fits beside the other services in today's 26 GiB, that the upgrade profile fits 96 GB, and the health script's ready, loading and down results. They build nothing and download nothing. Before this page was written, the pinned llama.cpp was also built in a scratch Linux container and started with these exact settings against a tiny generated test model. `/health`, the API key check, `/v1/models`, chat completions, `/metrics` and the CORS rule all behaved as described here. No real model was run.
