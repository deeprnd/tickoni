/// fd_aes_gcm_ossl.c - OpenSSL EVP wrapper for AES-GCM
///
/// Implements the three public AES-GCM functions (fd_aes_128_gcm_init,
/// fd_aes_gcm_encrypt, fd_aes_gcm_decrypt) using OpenSSL 3.x EVP API.
/// This replaces the hand-tuned x86_64 assembly (.S) files while
/// maintaining the exact same public API.
///
/// The EVP API is the recommended OpenSSL interface and uses hardware-
/// accelerated AES-NI/GCM instructions automatically on x86_64. On ARM,
/// it uses NEON crypto instructions.
///
/// Key design decisions:
/// - Opaque struct wrapping EVP_CIPHER_CTX* — callers don't see EVP internals
/// - FD_TEST macros for EVP errors (they shouldn't happen with correct inputs)
/// - Tag placement matches existing API contract (encrypt: output param,
///   decrypt: input param)
/// - AAD processed separately via EVP_EncryptUpdate/DecryptUpdate with
///   NULL output buffer (correct EVP GCM pattern)
/// - No struct memset: struct only holds pointer, per-packet stack alloc
///   callers (fd_aes_gcm_t aes_gcm[1]) don't need zeroing
///
/// See: doc/execution/plans/v2.10-s2-5.md

#include "fd_aes_gcm.h"

#if FD_HAS_OPENSSL

#include <openssl/evp.h>
#include <openssl/err.h>
#include <string.h>

struct fd_aes_gcm_ossl {
    EVP_CIPHER_CTX *ctx;
};

void
fd_aes_128_gcm_init(fd_aes_gcm_t *aes_gcm,
                    uchar const    key[16],
                    uchar const    iv[12]) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    FD_TEST(ctx);

    int ok = EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
    FD_TEST(ok);

    // Set IV length (12 bytes for GCM)
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
    FD_TEST(ok);

    // Set key and IV
    ok = EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
    FD_TEST(ok);

    aes_gcm->ctx = ctx;
}

void
fd_aes_gcm_encrypt(fd_aes_gcm_t *aes_gcm,
                   uchar *        c,
                   uchar const *  p,
                   ulong          sz,
                   uchar const *  aad,
                   ulong          aad_sz,
                   uchar          tag[16]) {
    EVP_CIPHER_CTX *ctx = aes_gcm->ctx;
    int outlen = 0;
    int taglen = 16;

    // Process AAD first (if present)
    if (aad && aad_sz) {
        int ok = EVP_EncryptUpdate(ctx, NULL, &outlen, aad, (int)aad_sz);
        FD_TEST(ok);
    }

    // Encrypt data
    if (sz) {
        int ok = EVP_EncryptUpdate(ctx, c, &outlen, p, (int)sz);
        FD_TEST(ok);
    }

    // Finalize — writes the authentication tag to c + outlen
    int ok = EVP_EncryptFinal_ex(ctx, c + outlen, &outlen);
    FD_TEST(ok);

    // Retrieve the tag
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
    FD_TEST(ok);
}

int
fd_aes_gcm_decrypt(fd_aes_gcm_t *aes_gcm,
                   uchar const *  c,
                   uchar *        p,
                   ulong          sz,
                   uchar const *  aad,
                   ulong          aad_sz,
                   uchar const    tag[16]) {
    EVP_CIPHER_CTX *ctx = aes_gcm->ctx;
    int outlen = 0;
    int ok;

    // Set expected tag BEFORE finalizing (required for verification)
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, (void *)tag);
    FD_TEST(ok);

    // Process AAD first (if present)
    if (aad && aad_sz) {
        ok = EVP_DecryptUpdate(ctx, NULL, &outlen, aad, (int)aad_sz);
        FD_TEST(ok);
    }

    // Decrypt data
    if (sz) {
        ok = EVP_DecryptUpdate(ctx, p, &outlen, c, (int)sz);
        FD_TEST(ok);
    }

    // Finalize — verifies the tag
    // Returns 1 if tag matches, 0 if authentication fails
    ok = EVP_DecryptFinal_ex(ctx, p + outlen, &outlen);
    return ok;
}

/* fd_aes_gcm_cleanup releases the OpenSSL context allocated by
   fd_aes_128_gcm_init.  Callers that allocate fd_aes_gcm_t on the stack
   (fd_aes_gcm_t aes_gcm[1]) should call this before the object goes
   out of scope. */

void
fd_aes_gcm_cleanup( fd_aes_gcm_t *aes_gcm ) {
#if FD_HAS_OPENSSL
    EVP_CIPHER_CTX_free( aes_gcm->ctx );
    aes_gcm->ctx = NULL;
#endif
}

#endif /* FD_HAS_OPENSSL */
