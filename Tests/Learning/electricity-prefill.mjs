import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const source=readFileSync(new URL('../../NEU-Lumen/Core/Models/ElectricityPaymentPrefill.swift',import.meta.url),'utf8');
const script=source.split('static let script = #"""')[1].split('"""#')[0];

function fixture(options={}) {
    const events=[], listeners={};
    class Input {
        get value(){return this._value??'';}
        set value(value){this._value=String(value);}
        constructor(properties={}) {
            Object.assign(this,{name:'elecroomno',id:'',type:'text',value:'',maxLength:-1,labels:[],placeholder:'',disabled:false,readOnly:false},properties);
            this.ownerDocument={defaultView:{HTMLInputElement:Input,Event:class {constructor(type){this.type=type;}}}};
        }
        getClientRects(){return this.hidden?[]:[{}];}
        getAttribute(key){return this[key]??null;}
        matches(selector){assert.equal(selector,'input');return true;}
        dispatchEvent(event){
            events.push(event.type);
            for(const listener of listeners[event.type]||[]) listener({target:this});
        }
    }
    const inputs=(options.inputs||[{}]).map(properties=>new Input(properties));
    const document={querySelectorAll(selector){assert.equal(selector,'input');return inputs;},
        addEventListener(type,listener){(listeners[type]??=[]).push(listener);}};
    const location={protocol:'https:',hostname:'pay.neu.edu.cn',port:'',pathname:'/openPayElecPagesDbdx51414E039.html',...options.location};
    const context=vm.createContext({document,location,room:options.room??'1010203'});
    const execute=()=>vm.runInContext('(function(){'+script+'})()',context);
    return {inputs,events,execute,context};
}

let f=fixture();
assert.equal(f.execute().status,'filled');
assert.equal(f.inputs[0].value,'1010203');
assert.deepEqual(f.events,['input','change']);
f.execute();
assert.equal(f.events.length,2,'repeat reads must not reapply a filled field');

f.inputs[0].value='';
f.inputs[0].dispatchEvent({type:'input'});
assert.equal(f.execute().status,'edited');
assert.equal(f.inputs[0].value,'','manual clearing must stay empty');
f.inputs[0].value='2020405';
assert.equal(f.execute().status,'edited');
assert.equal(f.inputs[0].value,'2020405','manual replacement must stay unchanged');
f.inputs.splice(0,1,...fixture().inputs);
assert.equal(f.execute().status,'edited');
assert.equal(f.inputs[0].value,'','a DOM replacement must not undo the user choice to edit the room');

f=fixture({inputs:[{value:'2020405'}]});
assert.equal(f.execute().status,'kept');
assert.equal(f.inputs[0].value,'2020405','school-selected room has priority');
assert.equal(f.events.length,0);

f=fixture({inputs:[]});
assert.equal(f.execute().status,'unavailable');
f.inputs.push(...fixture().inputs);
assert.equal(f.execute().status,'filled','delayed rendered input can be filled on the next guarded attempt');

for(const input of [
    {type:'hidden'}, {type:'password'}, {name:'amount'}, {maxLength:4}, {readOnly:true}, {disabled:true}, {hidden:true},
    {name:'room',labels:[{textContent:'寝室号'}]}, {name:'room',labels:[{textContent:'房间号'}]}, {pattern:'[0-9]{4}'}
]) {
    f=fixture({inputs:[input]});
    assert.equal(f.execute().status,'unavailable',JSON.stringify(input));
    assert.equal(f.inputs[0].value,'');
    assert.equal(f.events.length,0);
}

for(const input of [
    {name:'other',id:'elec_room_no'}, {name:'custom',labels:[{textContent:'宿舍房间码'}]},
    {name:'custom',placeholder:'请输入7位房间号'}
]) {
    f=fixture({inputs:[input]});
    assert.equal(f.execute().status,'filled',JSON.stringify(input));
}

f=fixture({inputs:[{},{}]});
assert.equal(f.execute().status,'unavailable','ambiguous multiple fields must not be filled');
assert.equal(f.events.length,0);
for(const location of [
    {hostname:'pay.neu.edu.cn.evil.example'}, {protocol:'http:'}, {port:'8443'},
    {pathname:'/openPortal'}, {pathname:'/openPayElecPagesDbdx51414E039.html/extra'}
]) {
    f=fixture({location});assert.equal(f.execute().status,'unavailable');assert.equal(f.events.length,0);
}
for(const room of ['','1234','1010203&amount=100','１２３４５６７']) {
    f=fixture({room});assert.equal(f.execute().status,'unavailable');assert.equal(f.events.length,0);
}
console.log('Electricity prefill: empty-only, user edits, delayed rendering, field ambiguity, amount exclusion and exact origin checks passed.');
