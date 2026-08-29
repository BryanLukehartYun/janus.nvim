" A shim colorscheme: it renders a 'light' variant but reports itself as
" 'janusone' -- mirrors real schemes like cyberdream-light whose colors_name
" is just 'cyberdream'. Used to test that revert re-sources on a same-name
" background change.
highlight clear
if exists('syntax_on') | syntax reset | endif
let g:colors_name = 'janusone'
let g:janus_variant = 'light'
