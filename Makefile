.PHONY: dev clean lint test format docs deploy

dev:
	mkdir -p ~/.local/share/nvim/site/pack/dev/start/ff.nvim
	stow -d .. -t ~/.local/share/nvim/site/pack/dev/start/ff.nvim ff.nvim

clean:
	rm -rf ~/.local/share/nvim/site/pack/dev

test:
	timeout 60 nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

lint:
	# https://luals.github.io/#install
	VIMRUNTIME="$$(nvim --headless --clean -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa')" lua-language-server --check=./lua --checklevel=Warning --configpath=$(CURDIR)/.luarc.json
	VIMRUNTIME="$$(nvim --headless --clean -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa')" lua-language-server --check=./tests --checklevel=Warning --configpath=$(CURDIR)/.luarc.json

format:
	# https://github.com/JohnnyMorganz/StyLua#usage
	stylua .

docs:
	mkdir -p ./doc
	./deps/ts-vimdoc.nvim/scripts/docgen.sh README.md doc/ff.txt ff
	nvim --headless -c "helptags doc/" -c "qa"

deploy: test lint format docs
