DOTFILES_DIR := $(shell pwd)
TARGET       := $(HOME)
PACKAGES     := $(wildcard */)
PACKAGES     := $(PACKAGES:/=)
PACKAGES     := $(filter-out meta,$(PACKAGES))

STOW ?= stow
STOW_FLAGS := --dir=$(DOTFILES_DIR) --target=$(TARGET) --verbose=1

.PHONY: help list check install unlink relink

help:
	@echo "dotfiles Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make list      - パッケージ一覧を表示"
	@echo "  make check     - 衝突チェック（dry-run）"
	@echo "  make install   - 全パッケージを $$HOME に symlink"
	@echo "  make unlink    - 全パッケージを外す"
	@echo "  make relink    - 一度外してから貼り直す"
	@echo ""
	@echo "  make install-<pkg>  - 個別パッケージだけ install"
	@echo "  make check-<pkg>    - 個別パッケージだけ dry-run"

list:
	@printf '%s\n' $(PACKAGES)

check:
	@for pkg in $(PACKAGES); do \
		echo "[check] $$pkg"; \
		$(STOW) $(STOW_FLAGS) --no --stow $$pkg; \
	done

install:
	@for pkg in $(PACKAGES); do \
		echo "[install] $$pkg"; \
		$(STOW) $(STOW_FLAGS) --stow $$pkg; \
	done

unlink:
	@for pkg in $(PACKAGES); do \
		echo "[unlink] $$pkg"; \
		$(STOW) $(STOW_FLAGS) --delete $$pkg; \
	done

relink: unlink install

install-%:
	$(STOW) $(STOW_FLAGS) --stow $*

check-%:
	$(STOW) $(STOW_FLAGS) --no --stow $*

unlink-%:
	$(STOW) $(STOW_FLAGS) --delete $*
