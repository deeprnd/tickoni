$(call add-hdrs,fd_aes_base.h fd_aes_gcm.h)
$(call add-objs,fd_aes_base_ref fd_aes_gcm_ossl,fd_ballet)
$(call make-unit-test,test_aes,test_aes,fd_ballet fd_util,-lcrypto)
$(call run-unit-test,test_aes)
