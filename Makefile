all: architecture.png

architecture.png: architecture.uxf
	umlet \
		-action=convert \
		-format=png \
		-filename=$< \
		-output=$@.tmp
	pngquant --ext .png --force $@.tmp.png
	mv $@.tmp.png $@
