.PHONY: dev clean lint test docs deploy

dev:
	mkdir -p ~/.local/share/nvim/site/pack/dev/start/ff.nvim
	stow -d .. -t ~/.local/share/nvim/site/pack/dev/start/ff.nvim ff.nvim

clean:
	rm -rf ~/.local/share/nvim/site/pack/dev

lint:
	# https://luals.github.io/#install
	lua-language-server --check=./lua --checklevel=Error

test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

docs:
	./deps/ts-vimdoc.nvim/scripts/docgen.sh README.md doc/ff.txt ff
	nvim --headless -c "helptags doc/" -c "qa"

deploy: test lint docs

