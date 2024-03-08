help:
	@echo "INFO: make <tab> for targets"
.PHONY: help

-include proj_216.mk

clean:
	@rm -f *.log *.jou *.rpt
.PHONY: clean

ultraclean: clean ultraclean-zcu216
	@rm -rf top_216 package package.tar.gz package.zip
.PHONY: ultraclean
