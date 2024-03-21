help:
	@echo "INFO: make <tab> for targets"
.PHONY: help

GUI ?= 0

-include proj_216.mk

clean:
	@rm -f *.log *.jou *.rpt *.str
.PHONY: clean

ultraclean: clean ultraclean-zcu216-orig ultraclean-zcu216-ila ultraclean-zcu216-nn
	@rm -rf ip_local/*
	@rm -rf package package.tar.gz package.zip
.PHONY: ultraclean
