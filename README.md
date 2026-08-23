
# notebook.nvim 

"__Jupyter Notebook done properly__"

notebook.nvim is a Neovim plugin designed to make the interactions with Jupyter Notebook comfortable and fast.

`a GIF here`

### Description

The purpose of this plugin is to provide the user with as pure vim experience as possible during the work on a Jupyter Notebook. This is why the file you edit is a normal Python file so your other plugins will work perfectly with it. You can use all your vim motions, jump between other files, use LSP code actions at the same you write and execute Jupyter Notebook cells.

notebook.nvim creates a two window vertical split inside Neovim: **code** on the left and **results** on the right. Both windows are logically divided in cells and synchronized on scroll, so you can interact with code and view its results at the same time. 

Every cell is separated by a `# %% [<type>:<cell_id>]` line. You can write/delete those lines manually to create/delete a cell, but it is recommended to use the plugin commands as it is much faster.

### Requirements 

- Neovim v0.10.0+
- `jupyter` installed and in PATH (`pip install jupyter`)


### Quick install

The example is provided for `lazy.nvim`. Adapt the configuration for your plugin manager:

```lua 
{
	"Makariy/notebook.nvim",
	event = "BufReadCmd *.ipynb",

	dependencies = {
		"3rd/image.nvim", -- Optional: if you want inline image rendering
	},

	opts = {
		keymaps = {
			next_cell = "]d",
			previous_cell = "[d"
		}
	}
}
```


### Commands

- `:NotebookCellCreate`: Create a new empty code cell below the current cursor position
- `:NotebookCellDelete`: Delete the currently focused cell
- `:NotebookCellCut`: Cut the current cell to the internal notebook clipboard
- `:NotebookCellCopy`: Copy the current cell to the internal notebook clipboard
- `:NotebookCellPaste`: Paste the copied/cut cell below the current cell

- `:NotebookCellSplit`: Split the current cell into two distinct cells at the cursor's line
- `:NotebookCellJoin`: Merge the current cell with the cell immediately below it (must be the same type)

- `:NotebookCellSwitchType`: Toggle the current cell's type between Code and Markdown

- `:NotebookCellMoveAbove`: Swap the current cell with the one immediately above it
- `:NotebookCellMoveBelow`: Swap the current cell with the one immediately below it

- `:NotebookCellExecute`: Send the current cell to the Jupyter kernel for execution
- `:NotebookExecuteAll`: Execute all cells in the notebook sequentially
- `:NotebookExecuteAbove`: Execute all cells sequentially from the top down to the current cell
- `:NotebookExecuteBelow`: Execute the current cell and all subsequent cells sequentially

- `:NotebookGoToError`: Jump the cursor to the first cell that encountered an execution error
- `:NotebookGoToRunning`: Jump the cursor to the cell that is currently executing

- `:NotebookCellToggleOutput`: Hide or show the execution output for the current cell
- `:NotebookToggleOutputs`: Hide or show the execution outputs for all cells in the notebook globally
- `:NotebookFocus` [code|output]: Toggle distraction-free full-screen mode for the specified pane (or toggle the current pane if no argument is provided). 

- `:NotebookSave`: Safely serialize and write the notebook layout back to the .ipynb file on disk

- `:NotebookKernelStart`: Boot up a Jupyter kernel to execute Python code
- `:NotebookKernelRestart`: Restart the active kernel
- `:NotebookKernelInterrupt`: Send an interrupt signal (SIGINT) to halt the active execution
- `:NotebookKernelKill`: Forcefully shut down the active kernel

>[!tip]
>Use `:NotebookFocus` when writing long markdown lines. It hides the results window and turns on the text wrapping so you can type comfortably. 

### Mappings 

Clearly, you can map those commands to a keymap. Here is a simple and intuitive start:

```lua 
-- Cell create/copy/cut/paste 
vim.keymap.set("n", "<leader>nc", ":NotebookCellCreate<CR>")
vim.keymap.set("n", "<leader>ny", ":NotebookCellCopy<CR>")
vim.keymap.set("n", "<leader>nd", ":NotebookCellCut<CR>")
vim.keymap.set("n", "<leader>np", ":NotebookCellPaste<CR>")

-- Split/join cell 
vim.keymap.set("n", "<leader>nS", ":NotebookCellSplit<CR>")
vim.keymap.set("n", "<leader>nJ", ":NotebookCellJoin<CR>")

-- Cell type 
vim.keymap.set("n", "<leader>nt", ":NotebookCellSwitchType<CR>")

-- Move cells 
vim.keymap.set("n", "<leader>nk", ":NotebookCellMoveAbove<CR>")
vim.keymap.set("n", "<leader>nj", ":NotebookCellMoveBelow<CR>")

-- Execute cells 
vim.keymap.set("n", "<leader>ne", ":NotebookCellExecute<CR>")
vim.keymap.set("n", "<leader>nA", ":NotebookExecuteAll<CR>")
vim.keymap.set("n", "<leader>na", ":NotebookExecuteAbove<CR>")
vim.keymap.set("n", "<leader>nb", ":NotebookExecuteBelow<CR>")

-- Go to 
vim.keymap.set("n", "<leader>ngr", ":NotebookGoToRunning<CR>")
vim.keymap.set("n", "<leader>nge", ":NotebookGoToError<CR>")

-- Hiding outputs, focusing 
vim.keymap.set("n", "<leader>nf", ":NotebookFocus<CR>")
vim.keymap.set("n", "<leader>no", ":NotebookCellToggleOutput<CR>")
vim.keymap.set("n", "<leader>nO", ":NotebookToggleOutputs<CR>")

-- Save notebook 
vim.keymap.set("n", "<leader>ns", ":NotebookSave<CR>")

-- Interact with the kernel
vim.keymap.set("n", "<leader>ni", ":NotebookKernelInterrupt<CR>")
vim.keymap.set("n", "<leader>nq", ":NotebookKernelKill<CR>")
```

