const fs = require('fs');

const utilsCode = fs.readFileSync('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/html/js/utils.js', 'utf8');
const enCode = fs.readFileSync('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/html/lang/en.js', 'utf8');
const brCode = fs.readFileSync('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/html/lang/br.js', 'utf8');

var Lang = [];
let window = {};
let document = {
    createElement: () => ({ src: '', onload: () => {}, onerror: () => {} }),
    body: { appendChild: () => {} }
};
let $ = function(selector) {
    return {
        length: 0,
        append: () => {},
        find: (sel) => ({
            text: (t) => { console.log(`$.find('${sel}').text('${t}')`); },
            empty: () => {},
            append: (b) => { console.log(`$.find('${sel}').append(button: text='${b.text()}', class='${b.attr('class')}')`); },
            attr: () => {}
        }),
        modal: () => {},
        on: () => {}
    };
};
$.fn = {};
// Helper to create elements with $
let orig$ = $;
$ = function(html, props) {
    if (typeof html === 'string' && html.startsWith('<button')) {
        let text = props ? props.text : '';
        let cls = props ? props.class : '';
        let attrs = {};
        return {
            text: () => text,
            attr: (k, v) => v ? (attrs[k] = v) : (k === 'class' ? cls : attrs[k]),
            on: () => {}
        };
    }
    return orig$(html);
};

eval(utilsCode);
eval(enCode);
eval(brCode);

console.log('Testing with default locale ("en"):');
console.log('translate("confirmation_modal_title") ->', Utils.translate("confirmation_modal_title"));
console.log('translate("confirmation_modal_cancel_button") ->', Utils.translate("confirmation_modal_cancel_button"));
console.log('translate("confirmation_modal_confirm_button") ->', Utils.translate("confirmation_modal_confirm_button"));
console.log('translate("confirmation_modal_delete_party") ->', Utils.translate("confirmation_modal_delete_party"));

console.log('\nTesting with locale "br":');
Utils.setLocale("br");
console.log('translate("confirmation_modal_title") ->', Utils.translate("confirmation_modal_title"));
console.log('translate("confirmation_modal_cancel_button") ->', Utils.translate("confirmation_modal_cancel_button"));
console.log('translate("confirmation_modal_confirm_button") ->', Utils.translate("confirmation_modal_confirm_button"));
console.log('translate("confirmation_modal_delete_party") ->', Utils.translate("confirmation_modal_delete_party"));

console.log('\nTesting showDefaultDangerModal with locale "br":');
Utils.showDefaultDangerModal(() => {}, Utils.translate("confirmation_modal_delete_party"));
