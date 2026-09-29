const fs = require('fs');

let Lang = {};
const enCode = fs.readFileSync('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/html/lang/en.js', 'utf8');
const brCode = fs.readFileSync('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/html/lang/br.js', 'utf8');

eval(enCode.replace(/var Lang = \[\];/, ''));
eval(brCode.replace(/var Lang = \[\];/, ''));

console.log('Lang.br:');
console.log('title:', Lang['br']['confirmation_modal_title']);
console.log('cancel:', Lang['br']['confirmation_modal_cancel_button']);
console.log('confirm:', Lang['br']['confirmation_modal_confirm_button']);
console.log('delete_party:', Lang['br']['confirmation_modal_delete_party']);

console.log('\nLang.en:');
console.log('title:', Lang['en']['confirmation_modal_title']);
console.log('cancel:', Lang['en']['confirmation_modal_cancel_button']);
console.log('confirm:', Lang['en']['confirmation_modal_confirm_button']);
console.log('delete_party:', Lang['en']['confirmation_modal_delete_party']);
