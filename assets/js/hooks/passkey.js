import {fromAssertion, fromRegistration, toCreateOptions, toGetOptions} from "../webauthn_codec"

// One hook serves registration (settings), 2FA, and passkey-only login.
// The server owns all user-facing copy; this hook only reports error names.
const Passkey = {
  mounted() {
    if (!window.PublicKeyCredential) {
      this.pushEvent("webauthn:unsupported", {})
      return
    }

    this.handleEvent("webauthn:register", (options) => {
      this.ceremony(() =>
        navigator.credentials
          .create({publicKey: toCreateOptions(options), signal: this.newSignal()})
          .then((credential) => this.pushEvent("webauthn:registered", fromRegistration(credential))),
      )
    })

    this.handleEvent("webauthn:authenticate", (options) => {
      this.ceremony(() =>
        navigator.credentials
          .get({publicKey: toGetOptions(options), signal: this.newSignal()})
          .then((credential) => this.pushEvent("webauthn:asserted", fromAssertion(credential))),
      )
    })
  },

  destroyed() {
    this.abortPending()
  },

  newSignal() {
    this.abortPending()
    this.controller = new AbortController()
    return this.controller.signal
  },

  abortPending() {
    if (this.controller) this.controller.abort()
  },

  ceremony(run) {
    run().catch((error) => {
      if (error.name === "AbortError") return
      if (error.name === "SecurityError") {
        // Most likely cause in this template: the browser host doesn't match
        // the endpoint :url config (SUBDOMAIN / PHX_HOST / port).
        console.warn("WebAuthn origin/RP mismatch", error)
      }
      this.pushEvent("webauthn:error", {name: error.name, message: error.message})
    })
  },
}

export default Passkey
