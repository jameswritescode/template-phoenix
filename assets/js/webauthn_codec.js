// Pure conversions between the LiveView WebAuthn event payloads (base64url
// strings) and the ArrayBuffers the browser credential API speaks.

export function bufferToBase64url(buffer) {
  const view = new Uint8Array(buffer)
  let binary = ""
  for (const byte of view) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export function base64urlToBuffer(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
  const binary = atob(padded)
  const view = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i)
  return view.buffer
}

const decodeDescriptor = (descriptor) => ({...descriptor, id: base64urlToBuffer(descriptor.id)})

export function toCreateOptions(server) {
  const options = {...server, challenge: base64urlToBuffer(server.challenge)}
  if (server.user) options.user = {...server.user, id: base64urlToBuffer(server.user.id)}
  if (server.excludeCredentials) {
    options.excludeCredentials = server.excludeCredentials.map(decodeDescriptor)
  }
  return options
}

export function toGetOptions(server) {
  const options = {...server, challenge: base64urlToBuffer(server.challenge)}
  if (server.allowCredentials) {
    options.allowCredentials = server.allowCredentials.map(decodeDescriptor)
  }
  return options
}

export function fromRegistration(credential) {
  return {
    credential_id: bufferToBase64url(credential.rawId),
    attestation_object: bufferToBase64url(credential.response.attestationObject),
    client_data_json: bufferToBase64url(credential.response.clientDataJSON),
  }
}

export function fromAssertion(credential) {
  const response = credential.response
  return {
    credential_id: bufferToBase64url(credential.rawId),
    authenticator_data: bufferToBase64url(response.authenticatorData),
    signature: bufferToBase64url(response.signature),
    client_data_json: bufferToBase64url(response.clientDataJSON),
    user_handle: response.userHandle ? bufferToBase64url(response.userHandle) : null,
  }
}
