import {describe, expect, it} from "vitest"
import {
  base64urlToBuffer,
  bufferToBase64url,
  fromAssertion,
  fromRegistration,
  toCreateOptions,
  toGetOptions,
} from "../js/webauthn_codec"

const bytes = (...values) => new Uint8Array(values).buffer

describe("base64url round-trips", () => {
  it("handles lengths that need 0, 1, and 2 padding chars", () => {
    for (const input of [bytes(1), bytes(1, 2), bytes(1, 2, 3), bytes(251, 252, 253, 254)]) {
      const encoded = bufferToBase64url(input)
      expect(encoded).not.toMatch(/[+/=]/)
      expect(new Uint8Array(base64urlToBuffer(encoded))).toEqual(new Uint8Array(input))
    }
  })
})

describe("option conversion", () => {
  it("decodes challenge, user id, and credential descriptor ids", () => {
    const create = toCreateOptions({
      challenge: bufferToBase64url(bytes(9, 9)),
      user: {id: bufferToBase64url(bytes(1)), name: "a@b", displayName: "a@b"},
      excludeCredentials: [{type: "public-key", id: bufferToBase64url(bytes(7))}],
      attestation: "none",
    })
    expect(create.challenge).toBeInstanceOf(ArrayBuffer)
    expect(create.user.id).toBeInstanceOf(ArrayBuffer)
    expect(create.excludeCredentials[0].id).toBeInstanceOf(ArrayBuffer)
    expect(create.attestation).toBe("none")

    const get = toGetOptions({
      challenge: bufferToBase64url(bytes(3)),
      allowCredentials: [{type: "public-key", id: bufferToBase64url(bytes(5))}],
    })
    expect(get.allowCredentials[0].id).toBeInstanceOf(ArrayBuffer)

    const bare = toGetOptions({challenge: bufferToBase64url(bytes(3))})
    expect(bare.allowCredentials).toBeUndefined()
  })
})

describe("response extraction", () => {
  it("encodes registration and assertion responses, with null userHandle", () => {
    const registration = fromRegistration({
      rawId: bytes(1),
      response: {attestationObject: bytes(2), clientDataJSON: bytes(3)},
    })
    expect(registration).toEqual({
      credential_id: bufferToBase64url(bytes(1)),
      attestation_object: bufferToBase64url(bytes(2)),
      client_data_json: bufferToBase64url(bytes(3)),
    })

    const assertion = fromAssertion({
      rawId: bytes(1),
      response: {
        authenticatorData: bytes(2),
        signature: bytes(3),
        clientDataJSON: bytes(4),
        userHandle: null,
      },
    })
    expect(assertion.user_handle).toBeNull()
    expect(assertion.signature).toBe(bufferToBase64url(bytes(3)))
  })
})
