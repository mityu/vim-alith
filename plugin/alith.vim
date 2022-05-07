if exists('g:loaded_alith')
  finish
endif
let g:loaded_alith = 1

command! -range -nargs=* Alith call alith#Alith(<line1>, <line2>, <q-args>)
