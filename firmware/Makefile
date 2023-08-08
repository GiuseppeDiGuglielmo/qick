help:
	@echo "INFO: make <tab> for targets"
.PHONY: help

-include proj_111_rfbv2.mk
-include proj_216.mk

clean:
	@rm -f *.log *.jou *.rpt
.PHONY: clean

ultraclean: clean ultraclean-zcu111-rfbv2 ultraclean-zcu216
	@rm -rf top_216 top_111_rfbv2 package package.tar.gz package.zip
.PHONY: ultraclean
