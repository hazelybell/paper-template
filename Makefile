# Desitination file name prefix
NAME=paper

# Main SOURCE tex file here! vvv
MAIN=$(NAME).commented

FIGS=

INPUTS=abstract

BIBS=$(NAME).bib

LATEX=latex
LATEX_OPTS=-interaction=nonstopmode -halt-on-error
BIBTEX=bibtex

VIEWER=`cat ~/.viewer || which evince || which okular`
EDITOR=`cat ~/.editor || which emacs || which gvim || which vim || which vi`


JPGS=$(patsubst %.jpg,%.eps,$(filter %.jpg,$(FIGS)))
GIFS=$(patsubst %.gif,%.eps,$(filter %.gif,$(FIGS)))
PNGS=$(patsubst %.png,%.eps,$(filter %.png,$(FIGS)))
SVGS=$(patsubst %.svg,%.eps,$(filter %.svg,$(FIGS)))
SVGZS=$(patsubst %.svgz,%.eps,$(filter %.svgz,$(FIGS)))
PDFS=$(patsubst %.pdf,%.eps,$(filter %.pdf,$(FIGS)))
EPSS=$(filter %.eps,$(FIGS))

FIGS_TO_CONVERT=$(filter-out %.eps,$(FIGS))
CONVERTED_FIGS=$(addsuffix .eps,$(basename $(FIGS_TO_CONVERT)))
READY_FIGS=$(addsuffix .eps,$(basename $(FIGS)))
eq = $(and $(findstring $(1),$(2)),$(findstring $(2),$(1)))

.PHONY: all clean default view push commit zip

default: view

all: $(NAME).pdf

$(NAME).tex : $(MAIN).tex ltxclean.pl $(INPUTS)
ifneq ($(NAME),$(MAIN))
	perl ltxclean.pl $< >$@
endif

$(NAME).pdf: $(NAME).tex $(BIBS) $(READY_FIGS) $(INPUTS)
	$(LATEX) $(LATEX_OPTS) $(NAME).tex
	@if(grep "There were undefined references" $(NAME).log > /dev/null);\
	then \
		$(BIBTEX) $(NAME); \
		$(LATEX) $(LATEX_OPTS) $(NAME).tex; \
	fi
	@if(grep "Rerun" $(NAME).log > /dev/null);\
	then \
		$(LATEX) $(LATEX_OPTS) $(NAME).tex;\
	fi
	dvips -j0 -Ppdf -Pbuiltin35 -G0 -z $(NAME).dvi
	gs -q -dPDFA=2 \
	-dNOPAUSE -dBATCH -dSAFER -dPDFSETTINGS=/prepress \
	-dAutoFilterColorImages=false \
	-dAutoFilterGrayImages=false \
	-dAutoFilterMonoImages=false \
	-dColorImageFilter=/FlateEncode \
	-dGrayImageFilter=/FlateEncode \
	-dMonoImageFilter=/FlateEncode \
	-sDEVICE=pdfwrite -sOutputFile=$(NAME).pdf \
	-c .setpdfwrite \
	-f $(NAME).ps

clean:
	@rm -v *.blg *.bbl *.log *.aux $(NAME).dvi $(NAME).ps \
		$(NAME).spl $(NAME).zip $(NAME).out \
		$(CONVERTED_FIGS) || true
ifneq ($(NAME),$(MAIN))
	@rm -v $(NAME).tex || true
endif
	@rm -v $(NAME).pdf || echo Already Clean

view:	$(NAME).pdf
	$(VIEWER) $(NAME).pdf

edit:
	$(EDITOR) $(MAIN).tex $(BIBS)

# Use PS pipeline for maximum compatibility with random latex packages

$(SVGS) : %.eps : %.svg
	inkscape -b white -t -T --export-ignore-filters --export-eps=$@ $<

$(SVGZS) : %.eps : %.svgz
	inkscape -b white -t -T --export-ignore-filters --export-eps=$@ $<

$(JPGS) : %.eps : %.jpg
	anytopnm $< | pnmtops -nocenter -equalpixels -dpi 72 -noturn -rle -setpage - > $@

$(GIFS) : %.eps : %.gif
	anytopnm $< | pnmtops -nocenter -equalpixels -dpi 72 -noturn -rle -setpage - > $@

$(PNGS) : %.eps : %.png
	anytopnm $< | pnmtops -nocenter -equalpixels -dpi 72 -noturn -rle -setpage - > $@

%-crop.pdf: %.pdf
	pdfcrop $<

$(PDFS) : %.eps : %.pdf
	pdftops -eps $< $@

plots: 

push:	commit
	git push

commit:	
	git commit -av

zip : $(NAME).zip

$(NAME).zip : $(NAME).tex $(BIBS) $(READY_FIGS)
	zip $@ $^
