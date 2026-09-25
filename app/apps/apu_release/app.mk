APP_SRCS     += $(ROOT_PATH)/app/apps/apu_release/main.c
APP_INC_DIRS += $(ROOT_PATH)/app/apps/apu_release $(ROOT_PATH)/app/apps/hp_boot \
	$(SW_BUILD_DIR)/include

APU_RELEASE_ASSETS_H := $(SW_BUILD_DIR)/include/apu_release_assets.h

$(APU_RELEASE_ASSETS_H): $(APU_P5_BUNDLE) $(APU_P7_MODEL) $(APU_P9_APUC) \
	$(ROOT_PATH)/scripts/build_apu_release_assets.py \
	$(ROOT_PATH)/scripts/apu_codecs.py $(ROOT_PATH)/scripts/apu_kws.py \
	$(ROOT_PATH)/scripts/apu_kws_coeff.py \
	$(ROOT_PATH)/scripts/apu_p5_coefficients.py
	python3 $(ROOT_PATH)/scripts/build_apu_release_assets.py \
		--apumc $(APU_P5_BUNDLE) --apuc $(APU_P9_APUC) --apum $(APU_P7_MODEL) \
		--kws-corpus $(CACHE_ROOT)/sources/apu-kws-pcm \
		--output $@

$(SW_BUILD_DIR)/firmware: $(APU_RELEASE_ASSETS_H)
