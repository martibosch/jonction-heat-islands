.PHONY: create_environment register_ipykernel biophysical_table_shade

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_NAME = jonction-heat-islands

DATA_DIR = data
DATA_RAW_DIR := $(DATA_DIR)/raw
DATA_INTERIM_DIR := $(DATA_DIR)/interim
DATA_PROCESSED_DIR := $(DATA_DIR)/processed

MODELS_DIR = models

CODE_DIR = jonction_heat_islands

## rules
define MAKE_DATA_SUB_DIR
$(DATA_SUB_DIR): | $(DATA_DIR)
	mkdir $$@
endef
$(DATA_DIR):
	mkdir $@
$(foreach DATA_SUB_DIR, \
	$(DATA_RAW_DIR) $(DATA_INTERIM_DIR) $(DATA_PROCESSED_DIR), \
	$(eval $(MAKE_DATA_SUB_DIR)))
$(MODELS_DIR):
	mkdir $@

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## Set up python interpreter environment
create_environment:
	conda env create -f environment.yml

## Register the environment as an IPython kernel for Jupyter
register_ipykernel:
	python -m ipykernel install --user --name $(PROJECT_NAME) \
		--display-name "Python ($(PROJECT_NAME))"

## 1. Download the data
### variables
LULC_RASTER_ZENODO_URI = \
	https://zenodo.org/record/4589559/files/jonctioncarte.tif?download=1
TREE_CANOPY_ZENODO_URI = \
	https://zenodo.org/record/4589559/files/tree-canopy.tif?download=1
LULC_RASTER_TIF := $(DATA_RAW_DIR)/lulc-raster.tif
TREE_CANOPY_TIF := $(DATA_RAW_DIR)/tree-canopy.tif
$(LULC_RASTER_TIF): | $(DATA_RAW_DIR)
	wget $(LULC_RASTER_ZENODO_URI) -O $@
$(TREE_CANOPY_TIF): | $(DATA_RAW_DIR)
	wget $(TREE_CANOPY_ZENODO_URI) -O $@

## 2. Compute the shade column
### variables
BIOPHYSICAL_TABLE_CSV := $(DATA_RAW_DIR)/biophysical-table.csv
BIOPHYSICAL_TABLE_SHADE_CSV := $(DATA_PROCESSED_DIR)/biophysical-table.csv
#### code
MAKE_BIOPHYSICAL_TABLE_SHADE_PY := $(CODE_DIR)/make_biophysical_table_shade.py

$(BIOPHYSICAL_TABLE_SHADE_CSV):  $(LULC_RASTER_TIF) $(TREE_CANOPY_TIF) \
	$(BIOPHYSICAL_TABLE_CSV) | $(DATA_PROCESSED_DIR)
	python $(MAKE_BIOPHYSICAL_TABLE_SHADE_PY) $(LULC_RASTER_TIF) \
		$(TREE_CANOPY_TIF) $(BIOPHYSICAL_TABLE_CSV) $@
biophysical_table_shade: $(BIOPHYSICAL_TABLE_SHADE_CSV)

#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := show-help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: show-help
show-help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) == Darwin && echo '--no-init --raw-control-chars')
