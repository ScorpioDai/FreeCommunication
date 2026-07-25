# FreeCommunication preservation

For version 1.5.0 and later, preserve:

- The Git repository or a source ZIP.
- The corresponding `FreeCommunication-<version>.app.zip` release artifact.

The model repositories are intentionally separate and can be downloaded again
from Hugging Face. Existing model folders under `~/Documents/AI Models` may be
kept to avoid another multi-gigabyte download, but they are not source code.

Generated directories such as `.build`, `dist`, `work`, and `Backend/.venv`
are ignored by Git. The local backend environment is recreated with
`./script/setup_backend.sh` and is embedded only when producing an app bundle.

The archived 1.3.2 app and source ZIP remain useful as a snapshot of the last
model-bundled release. They are not part of the 1.5.0 Git history.

## First launch

Because models live in `~/Documents/AI Models`, macOS asks for access to the
Documents folder on first launch. The user must also grant Microphone and
Screen & System Audio Recording permissions for the relevant capture modes.

Local builds are ad-hoc signed. Developer ID signing and Apple notarization are
required for a normal internet distribution without a Gatekeeper trust prompt.
