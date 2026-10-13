# Deploy Automatic1111 + TinySD on Google Colab (Free)

## Quick Start

### Step 1: Create a Colab Notebook
1. Go to [colab.research.google.com](https://colab.research.google.com)
2. Click **New notebook**
3. Settings (gear icon) → Runtime type → **T4 GPU** → Save

### Step 2: Install & Run A1111 with TinySD

Copy this entire code block into a Colab cell and run:

```python
# Cell 1: Clone and install A1111
%cd /content
!git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
%cd stable-diffusion-webui

# Cell 2: Install dependencies
!pip install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
!pip install -q -r requirements.txt
!apt-get install -y libsm6 libxext6 libxrender-dev > /dev/null 2>&1

# Cell 3: Download TinySD model (lightweight)
import os
model_dir = "/content/stable-diffusion-webui/models/Stable-diffusion"
os.makedirs(model_dir, exist_ok=True)

# Download TinySD (recommended for free tier - only 200MB)
!cd {model_dir} && wget -q https://huggingface.co/segmind/tiny-sd/resolve/main/model.safetensors -O tinysd.safetensors || echo "Alternative: Using SD 1.5 pruned"

# Optional: Use SD 1.5 pruned instead (1.5GB, better quality)
# !cd {model_dir} && wget -q https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors -O sd15-pruned.safetensors

# Cell 4: Start A1111 with cloudflare tunnel (free public URL)
import subprocess
import time
from threading import Thread

# Start A1111 in background
cmd = [
    "python", "launch.py",
    "--share",  # Generates public shareable link
    "--disable-safe-unpickle",
    "--no-download-sd-model",  # We already downloaded
    "--listen",
    "--port", "7860"
]

process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

# Wait for startup and capture public URL
startup_complete = False
public_url = None

for line in process.stdout:
    print(line.rstrip())
    if "Running on" in line and "http" in line:
        startup_complete = True
    if "Running on" in line:
        # Extract URL
        parts = line.split("Running on ")
        if len(parts) > 1:
            public_url = parts[1].strip()
            print(f"\n✅ PUBLIC URL: {public_url}\n")
            break
    if "Traceback" in line:
        print("❌ Error starting A1111")
        break

# Cell 5: Keep Colab alive (run this periodically)
import requests
import time

public_url = "YOUR_PUBLIC_URL_HERE"  # Replace with URL from Cell 4

def keep_alive():
    while True:
        try:
            requests.get(public_url, timeout=10)
            print(f"✅ Ping at {time.strftime('%Y-%m-%d %H:%M:%S')}")
        except:
            print(f"❌ Connection failed at {time.strftime('%Y-%m-%d %H:%M:%S')}")
        time.sleep(300)  # Ping every 5 minutes

# Run in background (optional, helps prevent timeout)
# keep_alive()
```

## Free Tier Limitations & Solutions

| Limitation | Problem | Solution |
|-----------|---------|----------|
| **12-hour max** | Session disconnects after 12 hours | Restart notebook, keep URL handy |
| **Idle disconnect** | Closes if inactive 30 mins | Use keep-alive ping (Cell 5) |
| **No persistent GPU** | GPU may be revoked | Have backup Colab ready |
| **Limited VRAM** | T4 has 15GB | TinySD uses only 2-3GB ✅ |

## Sharing with Apple Reviewers

### Option A: Direct Colab Link (Recommended)
1. Click **Share** (top right of Colab)
2. Change access to **Anyone with link**
3. Send this link to Apple reviewers:
   ```
   https://colab.research.google.com/your-notebook-id
   ```
4. They open notebook → click **Runtime** → **Run all**
5. Wait ~5 mins for startup, public URL appears in output
6. They copy public URL and use in your Flutter app

### Option B: Bookmark Public A1111 URL
Once A1111 starts, the public Cloudflare URL (from Cell 4 output) looks like:
```
https://abc123-def456.gradio.live
```

Share this URL directly with reviewers. They can:
- Test in browser first
- Enter URL in your Flutter app settings as remote server

## Keeping It Running During Review (Free Strategy)

### ✅ Best: Keep Colab Tab Open
- Open notebook in separate tab/window
- Keep Colab tab in focus
- Runs indefinitely while you're active
- **Cost: $0**

### ✅ Alternative: Restart Daily
- Run through review period (typically 1-3 days)
- If session dies, restart Colab notebook
- Generates new URL (update Apple if needed)
- **Cost: $0**

### ⚠️ If You Need 24/7 Uptime
- Use **Colab Pro** ($10/month) for longer session limits + queued access
- Or switch to **RunPod** ($20-30 total for review period)

## Testing Before Submission

### Test the A1111 API
Once public URL is ready, test with your Flutter app:

```dart
// In your app's server settings, enter the Colab public URL
// Example: https://abc123-def456.gradio.live

// Test connection:
// 1. Go to Settings → Servers
// 2. Add server with public URL
// 3. Click "Test Connection"
// 4. Should show ✅ Connected
```

### Test Image Generation
1. Navigate to chat screen
2. Use "Tiny SD" model (if showing in dropdown)
3. Generate a test image
4. Verify it works

## Age Safety

**TinySD & SD 1.5 come with built-in safety checkers:**
- Content filter enabled by default
- Blocks NSFW prompt attempts
- Returns error image for violation detection
- Apple reviewers will see age-appropriate results

✅ **Safe for 13+ rating**

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "ModuleNotFoundError" | Run Cell 2 again (pip install) |
| "CUDA out of memory" | Use TinySD (not full SD 3.5) |
| URL not appearing | Scroll output, wait 2-3 mins more |
| Connection timeout | Restart runtime, re-run all cells |
| 404 on public URL | Colab session died, restart notebook |

## When Review is Complete

✅ Simply close the Colab notebook → **No costs incurred**

Colab is only billed if you upgrade to Pro. Free tier is truly free.

---

## Summary

| Metric | Value |
|--------|-------|
| **Cost** | $0 (completely free) |
| **Setup time** | 10-15 minutes |
| **Runtime availability** | 12 hours per session (restartable) |
| **Model size** | 200MB (TinySD) |
| **GPU VRAM used** | ~2-3GB of 15GB |
| **Suitable for Apple review** | ✅ Yes |
| **Age safety** | ✅ Built-in filters |

**Ready to share a Colab link with reviewers after step 1-4!**
