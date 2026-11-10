Telugu AI Voice - PC voice server (unlimited, free)
==================================================

What it does
  Runs the IndicF5 voice AI on this Windows PC. The phone app then makes
  natural voices and cloned voices with NO daily limit and no cost.
  The phone and the PC must be on the same Wi-Fi, and this PC must be on.

First time (10-40 minutes, mostly downloading):
  1. Right-click the zip > Extract All. Open the extracted folder.
  2. Double-click  Telugu-Voice-PC-Server.bat
     - If Windows says "Windows protected your PC": click More info > Run anyway.
  3. It installs Python and the AI engine by itself. Wait.
  4. When asked, log in at the Hugging Face page that opens, click
     "Agree and access repository" if shown, and paste your hf_... token.
  5. When it says "PC voice server is ON", it shows an address like
        http://192.168.1.23:7860/k/482913
     In the phone app: Settings > My PC voice server > type that address > Connect.
  6. If Windows asks about the firewall: tick "Private networks", click Allow.

Every day after that:
  Double-click Telugu-Voice-PC-Server.bat and keep the window open.
  (The PC will not go to sleep while the window is open.)
  Close the window to stop it.

If the phone cannot connect:
  - Phone and PC on the same Wi-Fi? (Not mobile data.)
  - The address changes if the router gives the PC a new number - check the window.
  - The app automatically uses the free online server when the PC is off.

Speed
  With NVIDIA graphics: a few seconds per sentence. Without: about 20-60 seconds.

Problems
  Take a photo of the black window and send it to Claude.
  Repair.bat removes the installed engine so the next start installs it again.

Files are kept in %LOCALAPPDATA%\TeluguVoiceServer. Every address includes a
secret 6-digit code, so other people on the Wi-Fi cannot use your server.
IndicF5 is by AI4Bharat (IIT Madras); use it for personal, non-commercial purposes.
