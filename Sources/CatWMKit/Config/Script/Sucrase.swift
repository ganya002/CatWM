package enum Sucrase {
    static let source = ##"""
(()=>{var yi=Object.create;var{getPrototypeOf:Ti,defineProperty:j1,getOwnPropertyNames:bi}=Object;var q1=Object.prot\##
otype.hasOwnProperty;function wi(e){return this[e]}var Si,Ei,$1=(e,s,r)=>{var o=e!=null&&typeof e==="object";if(o){v\##
ar a=s?Si??=new WeakMap:Ei??=new WeakMap,u=a.get(e);if(u)return u}r=e!=null?yi(Ti(e)):{};let m=s||!e||!e.__esModule|\##
|!q1.call(e,"default")?j1(r,"default",{value:e,enumerable:!0}):r;if(e&&typeof e==="object"||typeof e==="function"){f\##
or(let x of bi(e))if(!q1.call(m,x))j1(m,x,{get:wi.bind(e,x),enumerable:!0})}if(o)a.set(e,m);return m};var H1=(e,s)=>\##
()=>(s||e((s={exports:{}}).exports,s),s.exports);var ur=H1(function(zn,Kn){(function(e,s){typeof zn==="object"&&type\##
of Kn<"u"?Kn.exports=s():typeof define==="function"&&define.amd?define(s):(e=typeof globalThis<"u"?globalThis:e||sel\##
f,e.resolveURI=s())})(zn,function(){let e=/^[\w+.-]+:\/\//,s=/^([\w+.-]+:)\/\/([^@/#?]*@)?([^:/#?]*)(:\d+)?(\/[^#?]*\##
)?(\?[^#]*)?(#.*)?/,r=/^file:(?:\/\/((?![a-z]:)[^/#?]*)?)?(\/?[^#?]*)(\?[^#]*)?(#.*)?/i;function o(I){return e.test(\##
I)}function a(I){return I.startsWith("//")}function u(I){return I.startsWith("/")}function m(I){return I.startsWith(\##
"file:")}function x(I){return/^[.?#]/.test(I)}function k(I){let N=s.exec(I);return y(N[1],N[2]||"",N[3],N[4]||"",N[5\##
]||"/",N[6]||"",N[7]||"")}function T(I){let N=r.exec(I),P=N[2];return y("file:","",N[1]||"","",u(P)?P:"/"+P,N[3]||""\##
,N[4]||"")}function y(I,N,P,W,B,j,Z){return{scheme:I,user:N,host:P,port:W,path:B,query:j,hash:Z,type:7}}function C(I\##
){if(a(I)){let P=k("http:"+I);return P.scheme="",P.type=6,P}if(u(I)){let P=k("http://foo.com"+I);return P.scheme="",\##
P.host="",P.type=5,P}if(m(I))return T(I);if(o(I))return k(I);let N=k("http://foo.com/"+I);return N.scheme="",N.host=\##
"",N.type=I?I.startsWith("?")?3:I.startsWith("#")?2:4:1,N}function L(I){if(I.endsWith("/.."))return I;let N=I.lastIn\##
dexOf("/");return I.slice(0,N+1)}function M(I,N){if(z(N,N.type),I.path==="/")I.path=N.path;else I.path=L(N.path)+I.p\##
ath}function z(I,N){let P=N<=4,W=I.path.split("/"),B=1,j=0,Z=!1;for(let se=1;se<W.length;se++){let ce=W[se];if(!ce){\##
Z=!0;continue}if(Z=!1,ce===".")continue;if(ce===".."){if(j)Z=!0,j--,B--;else if(P)W[B++]=ce;continue}W[B++]=ce,j++}l\##
et ae="";for(let se=1;se<B;se++)ae+="/"+W[se];if(!ae||Z&&!ae.endsWith("/.."))ae+="/";I.path=ae}function U(I,N){if(!I\##
&&!N)return"";let P=C(I),W=P.type;if(N&&W!==7){let j=C(N),Z=j.type;switch(W){case 1:P.hash=j.hash;case 2:P.query=j.q\##
uery;case 3:case 4:M(P,j);case 5:P.user=j.user,P.host=j.host,P.port=j.port;case 6:P.scheme=j.scheme}if(Z>W)W=Z}z(P,W\##
);let B=P.query+P.hash;switch(W){case 2:case 3:return B;case 4:{let j=P.path.slice(1);if(!j)return B||".";if(x(N||I)\##
&&!x(j))return"./"+j+B;return j+B}case 5:return P.path+B;default:return P.scheme+"//"+P.user+P.host+P.port+P.path+B}\##
}return U})});var ni=H1(function(Mt){Mt.__esModule=!0;Mt.LinesAndColumns=void 0;var bs=`
`,ti="\r",si=function(){function e(s){this.string=s;var r=[0];for(var o=0;o<s.length;)switch(s[o]){case bs:o+=bs.len\##
gth,r.push(o);break;case ti:if(o+=ti.length,s[o]===bs)o+=bs.length;r.push(o);break;default:o++;break}this.offsets=r}\##
return e.prototype.locationForIndex=function(s){if(s<0||s>this.string.length)return null;var r=0,o=this.offsets;whil\##
e(o[r+1]<=s)r++;var a=s-o[r];return{line:r,column:a}},e.prototype.indexForLocation=function(s){var{line:r,column:o}=\##
s;if(r<0||r>=this.offsets.length)return null;if(o<0||o>this.lengthOfLine(r))return null;return this.offsets[r]+o},e.\##
prototype.lengthOfLine=function(s){var r=this.offsets[s],o=s===this.offsets.length-1?this.string.length:this.offsets\##
[s+1];return o-r},e}();Mt.LinesAndColumns=si;Mt.default=si});var c;(function(e){e[e.NONE=0]="NONE";let r=1;e[e._abst\##
ract=r]="_abstract";let o=r+1;e[e._accessor=o]="_accessor";let a=o+1;e[e._as=a]="_as";let u=a+1;e[e._assert=u]="_ass\##
ert";let m=u+1;e[e._asserts=m]="_asserts";let x=m+1;e[e._async=x]="_async";let k=x+1;e[e._await=k]="_await";let T=k+\##
1;e[e._checks=T]="_checks";let y=T+1;e[e._constructor=y]="_constructor";let C=y+1;e[e._declare=C]="_declare";let L=C\##
+1;e[e._enum=L]="_enum";let M=L+1;e[e._exports=M]="_exports";let z=M+1;e[e._from=z]="_from";let U=z+1;e[e._get=U]="_\##
get";let I=U+1;e[e._global=I]="_global";let N=I+1;e[e._implements=N]="_implements";let P=N+1;e[e._infer=P]="_infer";\##
let W=P+1;e[e._interface=W]="_interface";let B=W+1;e[e._is=B]="_is";let j=B+1;e[e._keyof=j]="_keyof";let Z=j+1;e[e._\##
mixins=Z]="_mixins";let ae=Z+1;e[e._module=ae]="_module";let se=ae+1;e[e._namespace=se]="_namespace";let ce=se+1;e[e\##
._of=ce]="_of";let Be=ce+1;e[e._opaque=Be]="_opaque";let je=Be+1;e[e._out=je]="_out";let qe=je+1;e[e._override=qe]="\##
_override";let $e=qe+1;e[e._private=$e]="_private";let He=$e+1;e[e._protected=He]="_protected";let Ue=He+1;e[e._prot\##
o=Ue]="_proto";let We=Ue+1;e[e._public=We]="_public";let Ve=We+1;e[e._readonly=Ve]="_readonly";let Ge=Ve+1;e[e._requ\##
ire=Ge]="_require";let Xe=Ge+1;e[e._satisfies=Xe]="_satisfies";let Je=Xe+1;e[e._set=Je]="_set";let ze=Je+1;e[e._stat\##
ic=ze]="_static";let Ke=ze+1;e[e._symbol=Ke]="_symbol";let Ye=Ke+1;e[e._type=Ye]="_type";let Qe=Ye+1;e[e._unique=Qe]\##
="_unique";let ft=Qe+1;e[e._using=ft]="_using"})(c||(c={}));var t;(function(e){e[e.PRECEDENCE_MASK=15]="PRECEDENCE_M\##
ASK";let r=16;e[e.IS_KEYWORD=r]="IS_KEYWORD";let o=32;e[e.IS_ASSIGN=o]="IS_ASSIGN";let a=64;e[e.IS_RIGHT_ASSOCIATIVE\##
=a]="IS_RIGHT_ASSOCIATIVE";let u=128;e[e.IS_PREFIX=u]="IS_PREFIX";let m=256;e[e.IS_POSTFIX=m]="IS_POSTFIX";let x=512\##
;e[e.IS_EXPRESSION_START=x]="IS_EXPRESSION_START";let k=512;e[e.num=k]="num";let T=1536;e[e.bigint=T]="bigint";let y\##
=2560;e[e.decimal=y]="decimal";let C=3584;e[e.regexp=C]="regexp";let L=4608;e[e.string=L]="string";let M=5632;e[e.na\##
me=M]="name";let z=6144;e[e.eof=z]="eof";let U=7680;e[e.bracketL=U]="bracketL";let I=8192;e[e.bracketR=I]="bracketR"\##
;let N=9728;e[e.braceL=N]="braceL";let P=10752;e[e.braceBarL=P]="braceBarL";let W=11264;e[e.braceR=W]="braceR";let B\##
=12288;e[e.braceBarR=B]="braceBarR";let j=13824;e[e.parenL=j]="parenL";let Z=14336;e[e.parenR=Z]="parenR";let ae=153\##
60;e[e.comma=ae]="comma";let se=16384;e[e.semi=se]="semi";let ce=17408;e[e.colon=ce]="colon";let Be=18432;e[e.double\##
Colon=Be]="doubleColon";let je=19456;e[e.dot=je]="dot";let qe=20480;e[e.question=qe]="question";let $e=21504;e[e.que\##
stionDot=$e]="questionDot";let He=22528;e[e.arrow=He]="arrow";let Ue=23552;e[e.template=Ue]="template";let We=24576;\##
e[e.ellipsis=We]="ellipsis";let Ve=25600;e[e.backQuote=Ve]="backQuote";let Ge=27136;e[e.dollarBraceL=Ge]="dollarBrac\##
eL";let Xe=27648;e[e.at=Xe]="at";let Je=29184;e[e.hash=Je]="hash";let ze=29728;e[e.eq=ze]="eq";let Ke=30752;e[e.assi\##
gn=Ke]="assign";let Ye=32640;e[e.preIncDec=Ye]="preIncDec";let Qe=33664;e[e.postIncDec=Qe]="postIncDec";let ft=34432\##
;e[e.bang=ft]="bang";let ws=35456;e[e.tilde=ws]="tilde";let Ss=35841;e[e.pipeline=Ss]="pipeline";let Es=36866;e[e.nu\##
llishCoalescing=Es]="nullishCoalescing";let As=37890;e[e.logicalOR=As]="logicalOR";let Cs=38915;e[e.logicalAND=Cs]="\##
logicalAND";let Ns=39940;e[e.bitwiseOR=Ns]="bitwiseOR";let Ps=40965;e[e.bitwiseXOR=Ps]="bitwiseXOR";let Rs=41990;e[e\##
.bitwiseAND=Rs]="bitwiseAND";let vs=43015;e[e.equality=vs]="equality";let Ls=44040;e[e.lessThan=Ls]="lessThan";let D\##
s=45064;e[e.greaterThan=Ds]="greaterThan";let Fs=46088;e[e.relationalOrEqual=Fs]="relationalOrEqual";let Os=47113;e[\##
e.bitShiftL=Os]="bitShiftL";let Ms=48137;e[e.bitShiftR=Ms]="bitShiftR";let Bs=49802;e[e.plus=Bs]="plus";let js=50826\##
;e[e.minus=js]="minus";let qs=51723;e[e.modulo=qs]="modulo";let $s=52235;e[e.star=$s]="star";let Hs=53259;e[e.slash=\##
Hs]="slash";let Us=54348;e[e.exponent=Us]="exponent";let Ws=55296;e[e.jsxName=Ws]="jsxName";let Vs=56320;e[e.jsxText\##
=Vs]="jsxText";let Gs=57344;e[e.jsxEmptyText=Gs]="jsxEmptyText";let Xs=58880;e[e.jsxTagStart=Xs]="jsxTagStart";let J\##
s=59392;e[e.jsxTagEnd=Js]="jsxTagEnd";let zs=60928;e[e.typeParameterStart=zs]="typeParameterStart";let Ks=61440;e[e.\##
nonNullAssertion=Ks]="nonNullAssertion";let Ys=62480;e[e._break=Ys]="_break";let Qs=63504;e[e._case=Qs]="_case";let \##
Zs=64528;e[e._catch=Zs]="_catch";let en=65552;e[e._continue=en]="_continue";let tn=66576;e[e._debugger=tn]="_debugge\##
r";let sn=67600;e[e._default=sn]="_default";let nn=68624;e[e._do=nn]="_do";let rn=69648;e[e._else=rn]="_else";let on\##
=70672;e[e._finally=on]="_finally";let an=71696;e[e._for=an]="_for";let cn=73232;e[e._function=cn]="_function";let l\##
n=73744;e[e._if=ln]="_if";let un=74768;e[e._return=un]="_return";let pn=75792;e[e._switch=pn]="_switch";let fn=77456\##
;e[e._throw=fn]="_throw";let hn=77840;e[e._try=hn]="_try";let mn=78864;e[e._var=mn]="_var";let dn=79888;e[e._let=dn]\##
="_let";let kn=80912;e[e._const=kn]="_const";let xn=81936;e[e._while=xn]="_while";let gn=82960;e[e._with=gn]="_with"\##
;let _n=84496;e[e._new=_n]="_new";let In=85520;e[e._this=In]="_this";let yn=86544;e[e._super=yn]="_super";let Tn=875\##
68;e[e._class=Tn]="_class";let bn=88080;e[e._extends=bn]="_extends";let wn=89104;e[e._export=wn]="_export";let Sn=90\##
640;e[e._import=Sn]="_import";let En=91664;e[e._yield=En]="_yield";let An=92688;e[e._null=An]="_null";let Cn=93712;e\##
[e._true=Cn]="_true";let Nn=94736;e[e._false=Nn]="_false";let Pn=95256;e[e._in=Pn]="_in";let Rn=96280;e[e._instanceo\##
f=Rn]="_instanceof";let vn=97936;e[e._typeof=vn]="_typeof";let Ln=98960;e[e._void=Ln]="_void";let oi=99984;e[e._dele\##
te=oi]="_delete";let ii=100880;e[e._async=ii]="_async";let ai=101904;e[e._get=ai]="_get";let ci=102928;e[e._set=ci]=\##
"_set";let li=103952;e[e._declare=li]="_declare";let ui=104976;e[e._readonly=ui]="_readonly";let pi=106000;e[e._abst\##
ract=pi]="_abstract";let fi=107024;e[e._static=fi]="_static";let hi=107536;e[e._public=hi]="_public";let mi=108560;e\##
[e._private=mi]="_private";let di=109584;e[e._protected=di]="_protected";let ki=110608;e[e._override=ki]="_override"\##
;let xi=112144;e[e._as=xi]="_as";let gi=113168;e[e._enum=gi]="_enum";let _i=114192;e[e._type=_i]="_type";let Ii=1152\##
16;e[e._implements=Ii]="_implements"})(t||(t={}));function Dn(e){switch(e){case t.num:return"num";case t.bigint:retu\##
rn"bigint";case t.decimal:return"decimal";case t.regexp:return"regexp";case t.string:return"string";case t.name:retu\##
rn"name";case t.eof:return"eof";case t.bracketL:return"[";case t.bracketR:return"]";case t.braceL:return"{";case t.b\##
raceBarL:return"{|";case t.braceR:return"}";case t.braceBarR:return"|}";case t.parenL:return"(";case t.parenR:return\##
")";case t.comma:return",";case t.semi:return";";case t.colon:return":";case t.doubleColon:return"::";case t.dot:ret\##
urn".";case t.question:return"?";case t.questionDot:return"?.";case t.arrow:return"=>";case t.template:return"templa\##
te";case t.ellipsis:return"...";case t.backQuote:return"`";case t.dollarBraceL:return"${";case t.at:return"@";case t\##
.hash:return"#";case t.eq:return"=";case t.assign:return"_=";case t.preIncDec:return"++/--";case t.postIncDec:return\##
"++/--";case t.bang:return"!";case t.tilde:return"~";case t.pipeline:return"|>";case t.nullishCoalescing:return"??";\##
case t.logicalOR:return"||";case t.logicalAND:return"&&";case t.bitwiseOR:return"|";case t.bitwiseXOR:return"^";case\##
 t.bitwiseAND:return"&";case t.equality:return"==/!=";case t.lessThan:return"<";case t.greaterThan:return">";case t.\##
relationalOrEqual:return"<=/>=";case t.bitShiftL:return"<<";case t.bitShiftR:return">>/>>>";case t.plus:return"+";ca\##
se t.minus:return"-";case t.modulo:return"%";case t.star:return"*";case t.slash:return"/";case t.exponent:return"**"\##
;case t.jsxName:return"jsxName";case t.jsxText:return"jsxText";case t.jsxEmptyText:return"jsxEmptyText";case t.jsxTa\##
gStart:return"jsxTagStart";case t.jsxTagEnd:return"jsxTagEnd";case t.typeParameterStart:return"typeParameterStart";c\##
ase t.nonNullAssertion:return"nonNullAssertion";case t._break:return"break";case t._case:return"case";case t._catch:\##
return"catch";case t._continue:return"continue";case t._debugger:return"debugger";case t._default:return"default";ca\##
se t._do:return"do";case t._else:return"else";case t._finally:return"finally";case t._for:return"for";case t._functi\##
on:return"function";case t._if:return"if";case t._return:return"return";case t._switch:return"switch";case t._throw:\##
return"throw";case t._try:return"try";case t._var:return"var";case t._let:return"let";case t._const:return"const";ca\##
se t._while:return"while";case t._with:return"with";case t._new:return"new";case t._this:return"this";case t._super:\##
return"super";case t._class:return"class";case t._extends:return"extends";case t._export:return"export";case t._impo\##
rt:return"import";case t._yield:return"yield";case t._null:return"null";case t._true:return"true";case t._false:retu\##
rn"false";case t._in:return"in";case t._instanceof:return"instanceof";case t._typeof:return"typeof";case t._void:ret\##
urn"void";case t._delete:return"delete";case t._async:return"async";case t._get:return"get";case t._set:return"set";\##
case t._declare:return"declare";case t._readonly:return"readonly";case t._abstract:return"abstract";case t._static:r\##
eturn"static";case t._public:return"public";case t._private:return"private";case t._protected:return"protected";case\##
 t._override:return"override";case t._as:return"as";case t._enum:return"enum";case t._type:return"type";case t._impl\##
ements:return"implements";default:return""}}class re{constructor(e,s,r){this.startTokenIndex=e,this.endTokenIndex=s,\##
this.isFunctionScope=r}}class U1{constructor(e,s,r,o,a,u,m,x,k,T,y,C,L){this.potentialArrowAt=e,this.noAnonFunctionT\##
ype=s,this.inDisallowConditionalTypesContext=r,this.tokensLength=o,this.scopesLength=a,this.pos=u,this.type=m,this.c\##
ontextualKeyword=x,this.start=k,this.end=T,this.isType=y,this.scopeDepth=C,this.error=L}}class Y{constructor(){Y.pro\##
totype.__init.call(this),Y.prototype.__init2.call(this),Y.prototype.__init3.call(this),Y.prototype.__init4.call(this\##
),Y.prototype.__init5.call(this),Y.prototype.__init6.call(this),Y.prototype.__init7.call(this),Y.prototype.__init8.c\##
all(this),Y.prototype.__init9.call(this),Y.prototype.__init10.call(this),Y.prototype.__init11.call(this),Y.prototype\##
.__init12.call(this),Y.prototype.__init13.call(this)}__init(){this.potentialArrowAt=-1}__init2(){this.noAnonFunction\##
Type=!1}__init3(){this.inDisallowConditionalTypesContext=!1}__init4(){this.tokens=[]}__init5(){this.scopes=[]}__init\##
6(){this.pos=0}__init7(){this.type=t.eof}__init8(){this.contextualKeyword=c.NONE}__init9(){this.start=0}__init10(){t\##
his.end=0}__init11(){this.isType=!1}__init12(){this.scopeDepth=0}__init13(){this.error=null}snapshot(){return new U1\##
(this.potentialArrowAt,this.noAnonFunctionType,this.inDisallowConditionalTypesContext,this.tokens.length,this.scopes\##
.length,this.pos,this.type,this.contextualKeyword,this.start,this.end,this.isType,this.scopeDepth,this.error)}restor\##
eFromSnapshot(e){this.potentialArrowAt=e.potentialArrowAt,this.noAnonFunctionType=e.noAnonFunctionType,this.inDisall\##
owConditionalTypesContext=e.inDisallowConditionalTypesContext,this.tokens.length=e.tokensLength,this.scopes.length=e\##
.scopesLength,this.pos=e.pos,this.type=e.type,this.contextualKeyword=e.contextualKeyword,this.start=e.start,this.end\##
=e.end,this.isType=e.isType,this.scopeDepth=e.scopeDepth,this.error=e.error}}var l;(function(e){e[e.backSpace=8]="ba\##
ckSpace";let r=10;e[e.lineFeed=r]="lineFeed";let o=9;e[e.tab=o]="tab";let a=13;e[e.carriageReturn=a]="carriageReturn\##
";let u=14;e[e.shiftOut=u]="shiftOut";let m=32;e[e.space=m]="space";let x=33;e[e.exclamationMark=x]="exclamationMark\##
";let k=34;e[e.quotationMark=k]="quotationMark";let T=35;e[e.numberSign=T]="numberSign";let y=36;e[e.dollarSign=y]="\##
dollarSign";let C=37;e[e.percentSign=C]="percentSign";let L=38;e[e.ampersand=L]="ampersand";let M=39;e[e.apostrophe=\##
M]="apostrophe";let z=40;e[e.leftParenthesis=z]="leftParenthesis";let U=41;e[e.rightParenthesis=U]="rightParenthesis\##
";let I=42;e[e.asterisk=I]="asterisk";let N=43;e[e.plusSign=N]="plusSign";let P=44;e[e.comma=P]="comma";let W=45;e[e\##
.dash=W]="dash";let B=46;e[e.dot=B]="dot";let j=47;e[e.slash=j]="slash";let Z=48;e[e.digit0=Z]="digit0";let ae=49;e[\##
e.digit1=ae]="digit1";let se=50;e[e.digit2=se]="digit2";let ce=51;e[e.digit3=ce]="digit3";let Be=52;e[e.digit4=Be]="\##
digit4";let je=53;e[e.digit5=je]="digit5";let qe=54;e[e.digit6=qe]="digit6";let $e=55;e[e.digit7=$e]="digit7";let He\##
=56;e[e.digit8=He]="digit8";let Ue=57;e[e.digit9=Ue]="digit9";let We=58;e[e.colon=We]="colon";let Ve=59;e[e.semicolo\##
n=Ve]="semicolon";let Ge=60;e[e.lessThan=Ge]="lessThan";let Xe=61;e[e.equalsTo=Xe]="equalsTo";let Je=62;e[e.greaterT\##
han=Je]="greaterThan";let ze=63;e[e.questionMark=ze]="questionMark";let Ke=64;e[e.atSign=Ke]="atSign";let Ye=65;e[e.\##
uppercaseA=Ye]="uppercaseA";let Qe=66;e[e.uppercaseB=Qe]="uppercaseB";let ft=67;e[e.uppercaseC=ft]="uppercaseC";let \##
ws=68;e[e.uppercaseD=ws]="uppercaseD";let Ss=69;e[e.uppercaseE=Ss]="uppercaseE";let Es=70;e[e.uppercaseF=Es]="upperc\##
aseF";let As=71;e[e.uppercaseG=As]="uppercaseG";let Cs=72;e[e.uppercaseH=Cs]="uppercaseH";let Ns=73;e[e.uppercaseI=N\##
s]="uppercaseI";let Ps=74;e[e.uppercaseJ=Ps]="uppercaseJ";let Rs=75;e[e.uppercaseK=Rs]="uppercaseK";let vs=76;e[e.up\##
percaseL=vs]="uppercaseL";let Ls=77;e[e.uppercaseM=Ls]="uppercaseM";let Ds=78;e[e.uppercaseN=Ds]="uppercaseN";let Fs\##
=79;e[e.uppercaseO=Fs]="uppercaseO";let Os=80;e[e.uppercaseP=Os]="uppercaseP";let Ms=81;e[e.uppercaseQ=Ms]="uppercas\##
eQ";let Bs=82;e[e.uppercaseR=Bs]="uppercaseR";let js=83;e[e.uppercaseS=js]="uppercaseS";let qs=84;e[e.uppercaseT=qs]\##
="uppercaseT";let $s=85;e[e.uppercaseU=$s]="uppercaseU";let Hs=86;e[e.uppercaseV=Hs]="uppercaseV";let Us=87;e[e.uppe\##
rcaseW=Us]="uppercaseW";let Ws=88;e[e.uppercaseX=Ws]="uppercaseX";let Vs=89;e[e.uppercaseY=Vs]="uppercaseY";let Gs=9\##
0;e[e.uppercaseZ=Gs]="uppercaseZ";let Xs=91;e[e.leftSquareBracket=Xs]="leftSquareBracket";let Js=92;e[e.backslash=Js\##
]="backslash";let zs=93;e[e.rightSquareBracket=zs]="rightSquareBracket";let Ks=94;e[e.caret=Ks]="caret";let Ys=95;e[\##
e.underscore=Ys]="underscore";let Qs=96;e[e.graveAccent=Qs]="graveAccent";let Zs=97;e[e.lowercaseA=Zs]="lowercaseA";\##
let en=98;e[e.lowercaseB=en]="lowercaseB";let tn=99;e[e.lowercaseC=tn]="lowercaseC";let sn=100;e[e.lowercaseD=sn]="l\##
owercaseD";let nn=101;e[e.lowercaseE=nn]="lowercaseE";let rn=102;e[e.lowercaseF=rn]="lowercaseF";let on=103;e[e.lowe\##
rcaseG=on]="lowercaseG";let an=104;e[e.lowercaseH=an]="lowercaseH";let cn=105;e[e.lowercaseI=cn]="lowercaseI";let ln\##
=106;e[e.lowercaseJ=ln]="lowercaseJ";let un=107;e[e.lowercaseK=un]="lowercaseK";let pn=108;e[e.lowercaseL=pn]="lower\##
caseL";let fn=109;e[e.lowercaseM=fn]="lowercaseM";let hn=110;e[e.lowercaseN=hn]="lowercaseN";let mn=111;e[e.lowercas\##
eO=mn]="lowercaseO";let dn=112;e[e.lowercaseP=dn]="lowercaseP";let kn=113;e[e.lowercaseQ=kn]="lowercaseQ";let xn=114\##
;e[e.lowercaseR=xn]="lowercaseR";let gn=115;e[e.lowercaseS=gn]="lowercaseS";let _n=116;e[e.lowercaseT=_n]="lowercase\##
T";let In=117;e[e.lowercaseU=In]="lowercaseU";let yn=118;e[e.lowercaseV=yn]="lowercaseV";let Tn=119;e[e.lowercaseW=T\##
n]="lowercaseW";let bn=120;e[e.lowercaseX=bn]="lowercaseX";let wn=121;e[e.lowercaseY=wn]="lowercaseY";let Sn=122;e[e\##
.lowercaseZ=Sn]="lowercaseZ";let En=123;e[e.leftCurlyBrace=En]="leftCurlyBrace";let An=124;e[e.verticalBar=An]="vert\##
icalBar";let Cn=125;e[e.rightCurlyBrace=Cn]="rightCurlyBrace";let Nn=126;e[e.tilde=Nn]="tilde";let Pn=160;e[e.nonBre\##
akingSpace=Pn]="nonBreakingSpace";let Rn=5760;e[e.oghamSpaceMark=Rn]="oghamSpaceMark";let vn=8232;e[e.lineSeparator=\##
vn]="lineSeparator";let Ln=8233;e[e.paragraphSeparator=Ln]="paragraphSeparator"})(l||(l={}));var Ze,R,v,n,d,W1;funct\##
ion Re(){return W1++}function V1(e){if("pos"in e){let s=Ai(e.pos);e.message+=` (${s.line}:${s.column})`,e.loc=s}retu\##
rn e}class G1{constructor(e,s){this.line=e,this.column=s}}function Ai(e){let s=1,r=1;for(let o=0;o<e;o++)if(d.charCo\##
deAt(o)===l.lineFeed)s++,r=1;else r++;return new G1(s,r)}function X1(e,s,r,o){d=e,n=new Y,W1=1,Ze=s,R=r,v=o}function\##
 g(e){return n.contextualKeyword===e}function et(e){let s=ge();return s.type===t.name&&s.contextualKeyword===e}funct\##
ion V(e){return n.contextualKeyword===e&&p(t.name)}function q(e){if(!V(e))w()}function Q(){return i(t.eof)||i(t.brac\##
eR)||K()}function K(){let e=n.tokens[n.tokens.length-1],s=e?e.end:0;for(let r=s;r<n.start;r++){let o=d.charCodeAt(r)\##
;if(o===l.lineFeed||o===l.carriageReturn||o===8232||o===8233)return!0}return!1}function Bt(){let e=ht();for(let s=n.\##
end;s<e;s++){let r=d.charCodeAt(s);if(r===l.lineFeed||r===l.carriageReturn||r===8232||r===8233)return!0}return!1}fun\##
ction le(){return p(t.semi)||Q()}function F(){if(!le())w('Unexpected token, expected ";"')}function f(e){if(!p(e))w(\##
`Unexpected token, expected "${Dn(e)}"`)}function w(e="Unexpected token",s=n.start){if(n.error)return;let r=SyntaxEr\##
ror(e);r.pos=s,n.error=r,n.pos=d.length,S(t.eof)}var Fn=[9,11,12,l.space,l.nonBreakingSpace,l.oghamSpaceMark,8192,81\##
93,8194,8195,8196,8197,8198,8199,8200,8201,8202,8239,8287,12288,65279],On=/(?:\s|\/\/.*|\/\*[^]*?\*\/)*/g,Mn=new Uin\##
t8Array(65536);for(let e of Fn)Mn[e]=1;function Ci(e){if(e<48)return e===36;if(e<58)return!0;if(e<65)return!1;if(e<9\##
1)return!0;if(e<97)return e===95;if(e<123)return!0;if(e<128)return!1;throw Error("Should not be called with non-ASCI\##
I char code.")}var ee=new Uint8Array(65536);for(let e=0;e<128;e++)ee[e]=Ci(e)?1:0;ee.fill(1,128);for(let e of Fn)ee[\##
e]=0;ee[8232]=0;ee[8233]=0;var _e=ee.slice();for(let e=l.digit0;e<=l.digit9;e++)_e[e]=0;var Bn=new Int32Array(JSON.p\##
arse("[-1,27,783,918,1755,2376,2862,3483,-1,3699,-1,4617,4752,4833,5130,5508,5940,-1,6480,6939,7749,8181,8451,8613,-\##
1,8829,-1,-1,-1,54,243,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,432,-1,-1,-1,675,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,81,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,108,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,135,-1,-1,-1,-1,-1,-1,-1,-1,-1,162,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,189,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,216,-1,-1,-1,-1,-\##
1,-1,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,270,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,297,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,324,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,351,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,378,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,405,-1,-1,-1,-1,-1,-1,-1,-1,4,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,459,-1,-1,-1,-1,-1,594,-1,-1,-1,-1,-1,-1,486,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,513,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,540,-1,-1,-1,-1,-1,-1,8,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,567\##
,-1,-1,-1,-1,-1,-1,-1,10,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,621,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,648,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,12,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,702,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,729,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,756,-1,-\##
1,-1,-1,-1,-1,14,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,810,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,837,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,864,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,891,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,124961,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,945,-1,-1,-1,-1,-1,-1,1107,-1,-1,-1,1242,-1,-1,1350,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,972,1026,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,9\##
99,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,127009,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1053,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,1080,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,129057,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1134,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1161,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,1188,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,1215,-1,-1,-1,-1,-1,-1,-1,16,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,1269,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,1296,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1323,-\##
1,-1,-1,-1,-1,-1,-1,175137,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1377,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,1404,1620,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1431,-1,-1,-1,-\##
1,-1,-1,161825,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1458,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1485,-1,-1,-1,-1,-1,-1,-1,-1,1512,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1539,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1566,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,1593,-1,-1,-1,-1,-1,-1,-1,-1,18,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1647,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,1674,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,1701,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1728,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,13110\##
5,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1782,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,2349,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1809,1971,-1,-1,2106,-1,-1,-1,-1,-1,2241,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1836,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,1863,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1890,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1917,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1944,-1,-1,-1,-1,-1,-1,-1,-1,133153,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,1998,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,2025,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2052,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2079,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,20,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,2133,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2160,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2187,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2214,-1,-1,-1,-1,-1,-1,135201,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2268,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2295,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,2322,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,199969,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,137249,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2403,-1,2484,-1,-1,-1,-1,-1,-1,-1,-1,-1,2565,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2430,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2457,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,139297,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2511,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,2538,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,22,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2592,-1,-1,-1,2727,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2619,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,2646,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2\##
673,-1,-1,-1,-1,-1,-1,178209,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2700,-1,-1,-1,-1,-1,-1,-1,24,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2754,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2781,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,2808,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2835,-1,-1,-1,-1,-1,-1,-1,176161,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2889,-1,-1,-1,-1,-1,-1,-1,2997,-1,-1,-1,-1,-1,3159,-1,-1,3213,-1,-1,3294,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2916,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,2943,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,2970,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,189473,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3024,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3051,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3078,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3105,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3132,-1,141345,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3186,-1,-1,-1,-1,-1,-1,-1,-1,143393,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,3240,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3267,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,26,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,3321,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3348,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3375,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,3402,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,3429,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3456,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,146465,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3510,-1\##
,-1,-1,-1,-1,-1,3564,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,3537,-1,-1,-1,-1,-1,-1,28,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3591,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3618,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3645,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3672,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,30,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3726,-1,-1,-1,-1,-1,-1,3753,4077,-1,-1\##
,-1,-1,4590,-1,-1,-1,-1,-1,-1,-1,147489,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3780,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,3807,-1,-1,3996,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3834,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3861,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,3888,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,391\##
5,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3942,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3969,-1,-1,-1,-1,-1,-1,-1,32,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4023,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4050,-1,-1,-1,-1,-1,-1,181281,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,190513,-1,-1,-1,-1,-1,4104,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,4185,4401,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4131,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4158,-1,-1,-1,-1,-1,-1,-1,-1,34,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,4212,-1,-1,-1,-1,-1,-1,-1,4239,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4266,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4293,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4320,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4347,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,43\##
74,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,192561,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4428,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4455,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4482,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4509,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,4536,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,45\##
63,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,36,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,38,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,4644,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4671,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4698,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4725,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,40,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4779,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4806,-1,-1,-1,-1,-1,-1,15977\##
7,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4860,-1,-\##
1,-1,-1,-1,4995,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,4887,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,4914,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,4941,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,4968,-1,-1,-1,-1,-1,-1,-1,42,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,5022,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,5049,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5076,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5103,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,44,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5157,-1,-1,-1,5373,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,5427,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5184,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,5211,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,5238,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5265,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,5292,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5319,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5346,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,46,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5400,-1,-1,-1,168993,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5454,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5481,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,185377,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5535,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,5562,-1,-1,-1,-1,5697,5751,-1,-1,-1,-1,48,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,5589,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,5616,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,5643,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5670,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,50,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,5724,-1,-1,-1,-1,-1,-1,52,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,5778,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,5805,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5832,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5859,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,5886,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5913,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,54,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,5967,-1,-1,6345,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,5994,-1,-1,-1,-1,-1,6129,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,6021,-1,-1,-1,-1,-1,6048,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6075,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6102,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,56,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6156,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6183,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,6318,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6210,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6237,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,6264,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6291,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,58,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,60,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6372,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6399,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6426,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
6453,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6507,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,6534,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6696,-1,-1,6831,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6561,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6588,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6615,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6642,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6669,-1,64,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6723,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,6750,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,677\##
7,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6804,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,66,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,6858,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6885,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6912,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,149537,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6966,-1,-1,-1,7182,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,7236,7371,-1,7479,-1,7614,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,6993,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7020,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,7047,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7074,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7101,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,7128,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,7155,-1,-1,-1,-1,-1,-1,-1,68,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7209,-1,-1,-1,-1,-1,-1,70,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7263,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7290,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,7317,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7344,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,72,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7398,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7425,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7452,-1,-1,-\##
1,-1,-1,-1,-1,-1,173089,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,7506,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,7533,-1,-1,-1,-1,-1,-1,-1,-1,-1,7560,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,7587,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,151585,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7641,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,7668,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7695,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7722,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,74,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,7776,-1,-1,-1,-1,-1,-1,-1,-1,-1,7938,-1,-1,-1,-1,-1,-1,8046,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,7803,-1,-1,-1,-1,-1,-1,-1,-1,7857,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,7830,-1,-1,-1,-1,-1,-1,-1,171041,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7884,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7911,-1,-1,-1,154913,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7965,-1,-1,-1,8019,-1,-1,-1,-1,-1,-1,7\##
992,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,187425,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,155681,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8073,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8100,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,76,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8127,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8154,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,195873,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
8208,-1,-1,-1,-1,8343,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8235,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8262,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8289,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8316,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,78,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,8370,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,8397,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8424,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,80,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8478,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,8532,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,850\##
5,-1,-1,-1,-1,-1,-1,-1,-1,157729,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,-1,8559,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8586,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,197921,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8640,8748,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,8667,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8694,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8721,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
163873,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8775,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8802,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1\##
,-1,-1,-1,-1,-1,-1,165921,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,8856,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8883,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,8910,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-\##
1,-1,-1,-1,-1,-1,8937,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,183329,-1,-1,-1,-1,-1,-1,-1,\##
-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]"));function jn(){let e=0,s=0,r=n.pos;while(r<d.length){if(\##
s=d.charCodeAt(r),s<l.lowercaseA||s>l.lowercaseZ)break;let a=Bn[e+(s-l.lowercaseA)+1];if(a===-1)break;else e=a,r++}l\##
et o=Bn[e];if(o>-1&&!ee[s]){if(n.pos=r,o&1)S(o>>>1);else S(t.name,o>>>1);return}while(r<d.length){let a=d.charCodeAt\##
(r);if(ee[a])r++;else if(a===l.backslash){if(r+=2,d.charCodeAt(r)===l.leftCurlyBrace){while(r<d.length&&d.charCodeAt\##
(r)!==l.rightCurlyBrace)r++;r++}}else if(a===l.atSign&&d.charCodeAt(r+1)===l.atSign)r+=2;else break}n.pos=r,S(t.name\##
)}var _;(function(e){e[e.Access=0]="Access";let r=1;e[e.ExportAccess=r]="ExportAccess";let o=r+1;e[e.TopLevelDeclara\##
tion=o]="TopLevelDeclaration";let a=o+1;e[e.FunctionScopedDeclaration=a]="FunctionScopedDeclaration";let u=a+1;e[e.B\##
lockScopedDeclaration=u]="BlockScopedDeclaration";let m=u+1;e[e.ObjectShorthandTopLevelDeclaration=m]="ObjectShortha\##
ndTopLevelDeclaration";let x=m+1;e[e.ObjectShorthandFunctionScopedDeclaration=x]="ObjectShorthandFunctionScopedDecla\##
ration";let k=x+1;e[e.ObjectShorthandBlockScopedDeclaration=k]="ObjectShorthandBlockScopedDeclaration";let T=k+1;e[e\##
.ObjectShorthand=T]="ObjectShorthand";let y=T+1;e[e.ImportDeclaration=y]="ImportDeclaration";let C=y+1;e[e.ObjectKey\##
=C]="ObjectKey";let L=C+1;e[e.ImportAccess=L]="ImportAccess"})(_||(_={}));var oe;(function(e){e[e.NoChildren=0]="NoC\##
hildren";let r=1;e[e.OneChild=r]="OneChild";let o=r+1;e[e.StaticChildren=o]="StaticChildren";let a=o+1;e[e.KeyAfterP\##
ropSpread=a]="KeyAfterPropSpread"})(oe||(oe={}));function jt(e){let s=e.identifierRole;return s===_.TopLevelDeclarat\##
ion||s===_.FunctionScopedDeclaration||s===_.BlockScopedDeclaration||s===_.ObjectShorthandTopLevelDeclaration||s===_.\##
ObjectShorthandFunctionScopedDeclaration||s===_.ObjectShorthandBlockScopedDeclaration}function J1(e){let s=e.identif\##
ierRole;return s===_.FunctionScopedDeclaration||s===_.BlockScopedDeclaration||s===_.ObjectShorthandFunctionScopedDec\##
laration||s===_.ObjectShorthandBlockScopedDeclaration}function qt(e){let s=e.identifierRole;return s===_.TopLevelDec\##
laration||s===_.ObjectShorthandTopLevelDeclaration||s===_.ImportDeclaration}function z1(e){let s=e.identifierRole;re\##
turn s===_.TopLevelDeclaration||s===_.BlockScopedDeclaration||s===_.ObjectShorthandTopLevelDeclaration||s===_.Object\##
ShorthandBlockScopedDeclaration}function K1(e){let s=e.identifierRole;return s===_.FunctionScopedDeclaration||s===_.\##
ObjectShorthandFunctionScopedDeclaration}function Y1(e){return e.identifierRole===_.ObjectShorthandTopLevelDeclarati\##
on||e.identifierRole===_.ObjectShorthandBlockScopedDeclaration||e.identifierRole===_.ObjectShorthandFunctionScopedDe\##
claration}class tt{constructor(){this.type=n.type,this.contextualKeyword=n.contextualKeyword,this.start=n.start,this\##
.end=n.end,this.scopeDepth=n.scopeDepth,this.isType=n.isType,this.identifierRole=null,this.jsxRole=null,this.shadows\##
Global=!1,this.isAsyncOperation=!1,this.contextId=null,this.rhsEndIndex=null,this.isExpression=!1,this.numNullishCoa\##
lesceStarts=0,this.numNullishCoalesceEnds=0,this.isOptionalChainStart=!1,this.isOptionalChainEnd=!1,this.subscriptSt\##
artIndex=null,this.nullishStartIndex=null}}function h(){n.tokens.push(new tt),Un()}function de(){n.tokens.push(new t\##
t),n.start=n.pos,Ui()}function Q1(){if(n.type===t.assign)--n.pos;qi()}function A(e){for(let r=n.tokens.length-e;r<n.\##
tokens.length;r++)n.tokens[r].isType=!0;let s=n.isType;return n.isType=!0,s}function E(e){n.isType=e}function p(e){i\##
f(i(e))return h(),!0;else return!1}function $t(e){let s=n.isType;n.isType=!0,p(e),n.isType=s}function i(e){return n.\##
type===e}function O(){let e=n.snapshot();h();let s=n.type;return n.restoreFromSnapshot(e),s}class Z1{constructor(e,s\##
){this.type=e,this.contextualKeyword=s}}function ge(){let e=n.snapshot();h();let s=n.type,r=n.contextualKeyword;retu\##
rn n.restoreFromSnapshot(e),new Z1(s,r)}function ht(){return $n(n.pos)}function $n(e){On.lastIndex=e;let s=On.exec(d\##
);return e+s[0].length}function Hn(){return d.charCodeAt(ht())}function Un(){if(Vn(),n.start=n.pos,n.pos>=d.length){\##
let e=n.tokens;if(e.length>=2&&e[e.length-1].start>=d.length&&e[e.length-2].start>=d.length)w("Unexpectedly reached \##
the end of input.");S(t.eof);return}Ni(d.charCodeAt(n.pos))}function Ni(e){if(_e[e]||e===l.backslash||e===l.atSign&&\##
d.charCodeAt(n.pos+1)===l.atSign)jn();else Gn(e)}function Pi(){while(d.charCodeAt(n.pos)!==l.asterisk||d.charCodeAt(\##
n.pos+1)!==l.slash)if(n.pos++,n.pos>d.length){w("Unterminated comment",n.pos-2);return}n.pos+=2}function Wn(e){let s\##
=d.charCodeAt(n.pos+=e);if(n.pos<d.length)while(s!==l.lineFeed&&s!==l.carriageReturn&&s!==l.lineSeparator&&s!==l.par\##
agraphSeparator&&++n.pos<d.length)s=d.charCodeAt(n.pos)}function Vn(){while(n.pos<d.length){let e=d.charCodeAt(n.pos\##
);switch(e){case l.carriageReturn:if(d.charCodeAt(n.pos+1)===l.lineFeed)++n.pos;case l.lineFeed:case l.lineSeparator\##
:case l.paragraphSeparator:++n.pos;break;case l.slash:switch(d.charCodeAt(n.pos+1)){case l.asterisk:n.pos+=2,Pi();br\##
eak;case l.slash:Wn(2);break;default:return}break;default:if(Mn[e])++n.pos;else return}}}function S(e,s=c.NONE){n.en\##
d=n.pos,n.type=e,n.contextualKeyword=s}function Ri(){let e=d.charCodeAt(n.pos+1);if(e>=l.digit0&&e<=l.digit9){tr(!0)\##
;return}if(e===l.dot&&d.charCodeAt(n.pos+2)===l.dot)n.pos+=3,S(t.ellipsis);else++n.pos,S(t.dot)}function vi(){if(d.c\##
harCodeAt(n.pos+1)===l.equalsTo)D(t.assign,2);else D(t.slash,1)}function Li(e){let s=e===l.asterisk?t.star:t.modulo,\##
r=1,o=d.charCodeAt(n.pos+1);if(e===l.asterisk&&o===l.asterisk)r++,o=d.charCodeAt(n.pos+2),s=t.exponent;if(o===l.equa\##
lsTo&&d.charCodeAt(n.pos+2)!==l.greaterThan)r++,s=t.assign;D(s,r)}function Di(e){let s=d.charCodeAt(n.pos+1);if(s===\##
e){if(d.charCodeAt(n.pos+2)===l.equalsTo)D(t.assign,3);else D(e===l.verticalBar?t.logicalOR:t.logicalAND,2);return}i\##
f(e===l.verticalBar){if(s===l.greaterThan){D(t.pipeline,2);return}else if(s===l.rightCurlyBrace&&v){D(t.braceBarR,2)\##
;return}}if(s===l.equalsTo){D(t.assign,2);return}D(e===l.verticalBar?t.bitwiseOR:t.bitwiseAND,1)}function Fi(){if(d.\##
charCodeAt(n.pos+1)===l.equalsTo)D(t.assign,2);else D(t.bitwiseXOR,1)}function Oi(e){let s=d.charCodeAt(n.pos+1);if(\##
s===e){D(t.preIncDec,2);return}if(s===l.equalsTo)D(t.assign,2);else if(e===l.plusSign)D(t.plus,1);else D(t.minus,1)}\##
function Mi(){let e=d.charCodeAt(n.pos+1);if(e===l.lessThan){if(d.charCodeAt(n.pos+2)===l.equalsTo){D(t.assign,3);re\##
turn}if(n.isType)D(t.lessThan,1);else D(t.bitShiftL,2);return}if(e===l.equalsTo)D(t.relationalOrEqual,2);else D(t.le\##
ssThan,1)}function er(){if(n.isType){D(t.greaterThan,1);return}let e=d.charCodeAt(n.pos+1);if(e===l.greaterThan){let\##
 s=d.charCodeAt(n.pos+2)===l.greaterThan?3:2;if(d.charCodeAt(n.pos+s)===l.equalsTo){D(t.assign,s+1);return}D(t.bitSh\##
iftR,s);return}if(e===l.equalsTo)D(t.relationalOrEqual,2);else D(t.greaterThan,1)}function Ht(){if(n.type===t.greate\##
rThan)n.pos-=1,er()}function Bi(e){let s=d.charCodeAt(n.pos+1);if(s===l.equalsTo){D(t.equality,d.charCodeAt(n.pos+2)\##
===l.equalsTo?3:2);return}if(e===l.equalsTo&&s===l.greaterThan){n.pos+=2,S(t.arrow);return}D(e===l.equalsTo?t.eq:t.b\##
ang,1)}function ji(){let e=d.charCodeAt(n.pos+1),s=d.charCodeAt(n.pos+2);if(e===l.questionMark&&!(v&&n.isType))if(s=\##
==l.equalsTo)D(t.assign,3);else D(t.nullishCoalescing,2);else if(e===l.dot&&!(s>=l.digit0&&s<=l.digit9))n.pos+=2,S(t\##
.questionDot);else++n.pos,S(t.question)}function Gn(e){switch(e){case l.numberSign:++n.pos,S(t.hash);return;case l.d\##
ot:Ri();return;case l.leftParenthesis:++n.pos,S(t.parenL);return;case l.rightParenthesis:++n.pos,S(t.parenR);return;\##
case l.semicolon:++n.pos,S(t.semi);return;case l.comma:++n.pos,S(t.comma);return;case l.leftSquareBracket:++n.pos,S(\##
t.bracketL);return;case l.rightSquareBracket:++n.pos,S(t.bracketR);return;case l.leftCurlyBrace:if(v&&d.charCodeAt(n\##
.pos+1)===l.verticalBar)D(t.braceBarL,2);else++n.pos,S(t.braceL);return;case l.rightCurlyBrace:++n.pos,S(t.braceR);r\##
eturn;case l.colon:if(d.charCodeAt(n.pos+1)===l.colon)D(t.doubleColon,2);else++n.pos,S(t.colon);return;case l.questi\##
onMark:ji();return;case l.atSign:++n.pos,S(t.at);return;case l.graveAccent:++n.pos,S(t.backQuote);return;case l.digi\##
t0:{let s=d.charCodeAt(n.pos+1);if(s===l.lowercaseX||s===l.uppercaseX||s===l.lowercaseO||s===l.uppercaseO||s===l.low\##
ercaseB||s===l.uppercaseB){$i();return}}case l.digit1:case l.digit2:case l.digit3:case l.digit4:case l.digit5:case l\##
.digit6:case l.digit7:case l.digit8:case l.digit9:tr(!1);return;case l.quotationMark:case l.apostrophe:Hi(e);return;\##
case l.slash:vi();return;case l.percentSign:case l.asterisk:Li(e);return;case l.verticalBar:case l.ampersand:Di(e);r\##
eturn;case l.caret:Fi();return;case l.plusSign:case l.dash:Oi(e);return;case l.lessThan:Mi();return;case l.greaterTh\##
an:er();return;case l.equalsTo:case l.exclamationMark:Bi(e);return;case l.tilde:D(t.tilde,1);return;default:break}w(\##
`Unexpected character '${String.fromCharCode(e)}'`,n.pos)}function D(e,s){n.pos+=s,S(e)}function qi(){let e=n.pos,s=\##
!1,r=!1;for(;;){if(n.pos>=d.length){w("Unterminated regular expression",e);return}let o=d.charCodeAt(n.pos);if(s)s=!\##
1;else{if(o===l.leftSquareBracket)r=!0;else if(o===l.rightSquareBracket&&r)r=!1;else if(o===l.slash&&!r)break;s=o===\##
l.backslash}++n.pos}++n.pos,Wi(),S(t.regexp)}function qn(){while(!0){let e=d.charCodeAt(n.pos);if(e>=l.digit0&&e<=l.\##
digit9||e===l.underscore)n.pos++;else break}}function $i(){n.pos+=2;while(!0){let s=d.charCodeAt(n.pos);if(s>=l.digi\##
t0&&s<=l.digit9||s>=l.lowercaseA&&s<=l.lowercaseF||s>=l.uppercaseA&&s<=l.uppercaseF||s===l.underscore)n.pos++;else b\##
reak}if(d.charCodeAt(n.pos)===l.lowercaseN)++n.pos,S(t.bigint);else S(t.num)}function tr(e){let s=!1,r=!1;if(!e)qn()\##
;let o=d.charCodeAt(n.pos);if(o===l.dot)++n.pos,qn(),o=d.charCodeAt(n.pos);if(o===l.uppercaseE||o===l.lowercaseE){if\##
(o=d.charCodeAt(++n.pos),o===l.plusSign||o===l.dash)++n.pos;qn(),o=d.charCodeAt(n.pos)}if(o===l.lowercaseN)++n.pos,s\##
=!0;else if(o===l.lowercaseM)++n.pos,r=!0;if(s){S(t.bigint);return}if(r){S(t.decimal);return}S(t.num)}function Hi(e)\##
{n.pos++;for(;;){if(n.pos>=d.length){w("Unterminated string constant");return}let s=d.charCodeAt(n.pos);if(s===l.bac\##
kslash)n.pos++;else if(s===e)break;n.pos++}n.pos++,S(t.string)}function Ui(){for(;;){if(n.pos>=d.length){w("Untermin\##
ated template");return}let e=d.charCodeAt(n.pos);if(e===l.graveAccent||e===l.dollarSign&&d.charCodeAt(n.pos+1)===l.l\##
eftCurlyBrace){if(n.pos===n.start&&i(t.template))if(e===l.dollarSign){n.pos+=2,S(t.dollarBraceL);return}else{++n.pos\##
,S(t.backQuote);return}S(t.template);return}if(e===l.backslash)n.pos++;n.pos++}}function Wi(){while(n.pos<d.length){\##
let e=d.charCodeAt(n.pos);if(ee[e])n.pos++;else if(e===l.backslash){if(n.pos+=2,d.charCodeAt(n.pos)===l.leftCurlyBra\##
ce){while(n.pos<d.length&&d.charCodeAt(n.pos)!==l.rightCurlyBrace)n.pos++;n.pos++}}else break}}function ke(e,s=e.cur\##
rentIndex()){let r=s+1;if(Ut(e,r)){let o=e.identifierNameAtIndex(s);return{isType:!1,leftName:o,rightName:o,endIndex\##
:r}}if(r++,Ut(e,r))return{isType:!0,leftName:null,rightName:null,endIndex:r};if(r++,Ut(e,r))return{isType:!1,leftNam\##
e:e.identifierNameAtIndex(s),rightName:e.identifierNameAtIndex(s+2),endIndex:r};if(r++,Ut(e,r))return{isType:!0,left\##
Name:null,rightName:null,endIndex:r};throw Error(`Unexpected import/export specifier at ${s}`)}function Ut(e,s){let \##
r=e.tokens[s];return r.type===t.braceR||r.type===t.comma}var sr=new Map([["quot",'"'],["amp","&"],["apos","'"],["lt"\##
,"<"],["gt",">"],["nbsp","\u00a0"],["iexcl","\u00a1"],["cent","\u00a2"],["pound","\u00a3"],["curren","\u00a4"],["yen\##
","\u00a5"],["brvbar","\u00a6"],["sect","\u00a7"],["uml","\u00a8"],["copy","\u00a9"],["ordf","\u00aa"],["laquo","\u0\##
0ab"],["not","\u00ac"],["shy","\u00ad"],["reg","\u00ae"],["macr","\u00af"],["deg","\u00b0"],["plusmn","\u00b1"],["su\##
p2","\u00b2"],["sup3","\u00b3"],["acute","\u00b4"],["micro","\u00b5"],["para","\u00b6"],["middot","\u00b7"],["cedil"\##
,"\u00b8"],["sup1","\u00b9"],["ordm","\u00ba"],["raquo","\u00bb"],["frac14","\u00bc"],["frac12","\u00bd"],["frac34",\##
"\u00be"],["iquest","\u00bf"],["Agrave","\u00c0"],["Aacute","\u00c1"],["Acirc","\u00c2"],["Atilde","\u00c3"],["Auml"\##
,"\u00c4"],["Aring","\u00c5"],["AElig","\u00c6"],["Ccedil","\u00c7"],["Egrave","\u00c8"],["Eacute","\u00c9"],["Ecirc\##
","\u00ca"],["Euml","\u00cb"],["Igrave","\u00cc"],["Iacute","\u00cd"],["Icirc","\u00ce"],["Iuml","\u00cf"],["ETH","\\##
u00d0"],["Ntilde","\u00d1"],["Ograve","\u00d2"],["Oacute","\u00d3"],["Ocirc","\u00d4"],["Otilde","\u00d5"],["Ouml","\##
\u00d6"],["times","\u00d7"],["Oslash","\u00d8"],["Ugrave","\u00d9"],["Uacute","\u00da"],["Ucirc","\u00db"],["Uuml","\##
\u00dc"],["Yacute","\u00dd"],["THORN","\u00de"],["szlig","\u00df"],["agrave","\u00e0"],["aacute","\u00e1"],["acirc",\##
"\u00e2"],["atilde","\u00e3"],["auml","\u00e4"],["aring","\u00e5"],["aelig","\u00e6"],["ccedil","\u00e7"],["egrave",\##
"\u00e8"],["eacute","\u00e9"],["ecirc","\u00ea"],["euml","\u00eb"],["igrave","\u00ec"],["iacute","\u00ed"],["icirc",\##
"\u00ee"],["iuml","\u00ef"],["eth","\u00f0"],["ntilde","\u00f1"],["ograve","\u00f2"],["oacute","\u00f3"],["ocirc","\\##
u00f4"],["otilde","\u00f5"],["ouml","\u00f6"],["divide","\u00f7"],["oslash","\u00f8"],["ugrave","\u00f9"],["uacute",\##
"\u00fa"],["ucirc","\u00fb"],["uuml","\u00fc"],["yacute","\u00fd"],["thorn","\u00fe"],["yuml","\u00ff"],["OElig","\u\##
0152"],["oelig","\u0153"],["Scaron","\u0160"],["scaron","\u0161"],["Yuml","\u0178"],["fnof","\u0192"],["circ","\u02c\##
6"],["tilde","\u02dc"],["Alpha","\u0391"],["Beta","\u0392"],["Gamma","\u0393"],["Delta","\u0394"],["Epsilon","\u0395\##
"],["Zeta","\u0396"],["Eta","\u0397"],["Theta","\u0398"],["Iota","\u0399"],["Kappa","\u039a"],["Lambda","\u039b"],["\##
Mu","\u039c"],["Nu","\u039d"],["Xi","\u039e"],["Omicron","\u039f"],["Pi","\u03a0"],["Rho","\u03a1"],["Sigma","\u03a3\##
"],["Tau","\u03a4"],["Upsilon","\u03a5"],["Phi","\u03a6"],["Chi","\u03a7"],["Psi","\u03a8"],["Omega","\u03a9"],["alp\##
ha","\u03b1"],["beta","\u03b2"],["gamma","\u03b3"],["delta","\u03b4"],["epsilon","\u03b5"],["zeta","\u03b6"],["eta",\##
"\u03b7"],["theta","\u03b8"],["iota","\u03b9"],["kappa","\u03ba"],["lambda","\u03bb"],["mu","\u03bc"],["nu","\u03bd"\##
],["xi","\u03be"],["omicron","\u03bf"],["pi","\u03c0"],["rho","\u03c1"],["sigmaf","\u03c2"],["sigma","\u03c3"],["tau\##
","\u03c4"],["upsilon","\u03c5"],["phi","\u03c6"],["chi","\u03c7"],["psi","\u03c8"],["omega","\u03c9"],["thetasym","\##
\u03d1"],["upsih","\u03d2"],["piv","\u03d6"],["ensp","\u2002"],["emsp","\u2003"],["thinsp","\u2009"],["zwnj","\u200c\##
"],["zwj","\u200d"],["lrm","\u200e"],["rlm","\u200f"],["ndash","\u2013"],["mdash","\u2014"],["lsquo","\u2018"],["rsq\##
uo","\u2019"],["sbquo","\u201a"],["ldquo","\u201c"],["rdquo","\u201d"],["bdquo","\u201e"],["dagger","\u2020"],["Dagg\##
er","\u2021"],["bull","\u2022"],["hellip","\u2026"],["permil","\u2030"],["prime","\u2032"],["Prime","\u2033"],["lsaq\##
uo","\u2039"],["rsaquo","\u203a"],["oline","\u203e"],["frasl","\u2044"],["euro","\u20ac"],["image","\u2111"],["weier\##
p","\u2118"],["real","\u211c"],["trade","\u2122"],["alefsym","\u2135"],["larr","\u2190"],["uarr","\u2191"],["rarr","\##
\u2192"],["darr","\u2193"],["harr","\u2194"],["crarr","\u21b5"],["lArr","\u21d0"],["uArr","\u21d1"],["rArr","\u21d2"\##
],["dArr","\u21d3"],["hArr","\u21d4"],["forall","\u2200"],["part","\u2202"],["exist","\u2203"],["empty","\u2205"],["\##
nabla","\u2207"],["isin","\u2208"],["notin","\u2209"],["ni","\u220b"],["prod","\u220f"],["sum","\u2211"],["minus","\\##
u2212"],["lowast","\u2217"],["radic","\u221a"],["prop","\u221d"],["infin","\u221e"],["ang","\u2220"],["and","\u2227"\##
],["or","\u2228"],["cap","\u2229"],["cup","\u222a"],["int","\u222b"],["there4","\u2234"],["sim","\u223c"],["cong","\\##
u2245"],["asymp","\u2248"],["ne","\u2260"],["equiv","\u2261"],["le","\u2264"],["ge","\u2265"],["sub","\u2282"],["sup\##
","\u2283"],["nsub","\u2284"],["sube","\u2286"],["supe","\u2287"],["oplus","\u2295"],["otimes","\u2297"],["perp","\u\##
22a5"],["sdot","\u22c5"],["lceil","\u2308"],["rceil","\u2309"],["lfloor","\u230a"],["rfloor","\u230b"],["lang","\u23\##
29"],["rang","\u232a"],["loz","\u25ca"],["spades","\u2660"],["clubs","\u2663"],["hearts","\u2665"],["diams","\u2666"\##
]]);function mt(e){let[s,r]=nr(e.jsxPragma||"React.createElement"),[o,a]=nr(e.jsxFragmentPragma||"React.Fragment");r\##
eturn{base:s,suffix:r,fragmentBase:o,fragmentSuffix:a}}function nr(e){let s=e.indexOf(".");if(s===-1)s=e.length;retu\##
rn[e.slice(0,s),e.slice(s)]}class G{getPrefixCode(){return""}getHoistedCode(){return""}getSuffixCode(){return""}}cla\##
ss Ie extends G{__init(){this.lastLineNumber=1}__init2(){this.lastIndex=0}__init3(){this.filenameVarName=null}__init\##
4(){this.esmAutomaticImportNameResolutions={}}__init5(){this.cjsAutomaticModuleNameResolutions={}}constructor(e,s,r,\##
o,a){super();this.rootTransformer=e,this.tokens=s,this.importProcessor=r,this.nameManager=o,this.options=a,Ie.protot\##
ype.__init.call(this),Ie.prototype.__init2.call(this),Ie.prototype.__init3.call(this),Ie.prototype.__init4.call(this\##
),Ie.prototype.__init5.call(this),this.jsxPragmaInfo=mt(a),this.isAutomaticRuntime=a.jsxRuntime==="automatic",this.j\##
sxImportSource=a.jsxImportSource||"react"}process(){if(this.tokens.matches1(t.jsxTagStart))return this.processJSXTag\##
(),!0;return!1}getPrefixCode(){let e="";if(this.filenameVarName)e+=`const ${this.filenameVarName} = ${JSON.stringify\##
(this.options.filePath||"")};`;if(this.isAutomaticRuntime)if(this.importProcessor)for(let[s,r]of Object.entries(this\##
.cjsAutomaticModuleNameResolutions))e+=`var ${r} = require("${s}");`;else{let{createElement:s,...r}=this.esmAutomati\##
cImportNameResolutions;if(s)e+=`import {createElement as ${s}} from "${this.jsxImportSource}";`;let o=Object.entries\##
(r).map(([a,u])=>`${a} as ${u}`).join(", ");if(o){let a=this.jsxImportSource+(this.options.production?"/jsx-runtime"\##
:"/jsx-dev-runtime");e+=`import {${o}} from "${a}";`}}return e}processJSXTag(){let{jsxRole:e,start:s}=this.tokens.cu\##
rrentToken(),r=this.options.production?null:this.getElementLocationCode(s);if(this.isAutomaticRuntime&&e!==oe.KeyAft\##
erPropSpread)this.transformTagToJSXFunc(r,e);else this.transformTagToCreateElement(r)}getElementLocationCode(e){retu\##
rn`lineNumber: ${this.getLineNumberForIndex(e)}`}getLineNumberForIndex(e){let s=this.tokens.code;while(this.lastInde\##
x<e&&this.lastIndex<s.length){if(s[this.lastIndex]===`
`)this.lastLineNumber++;this.lastIndex++}return this.lastLineNumber}transformTagToJSXFunc(e,s){let r=s===oe.StaticCh\##
ildren;this.tokens.replaceToken(this.getJSXFuncInvocationCode(r));let o=null;if(this.tokens.matches1(t.jsxTagEnd))th\##
is.tokens.replaceToken(`${this.getFragmentCode()}, {`),this.processAutomaticChildrenAndEndProps(s);else{if(this.proc\##
essTagIntro(),this.tokens.appendCode(", {"),o=this.processProps(!0),this.tokens.matches2(t.slash,t.jsxTagEnd))this.t\##
okens.appendCode("}");else if(this.tokens.matches1(t.jsxTagEnd))this.tokens.removeToken(),this.processAutomaticChild\##
renAndEndProps(s);else throw Error("Expected either /> or > at the end of the tag.");if(o)this.tokens.appendCode(`, \##
${o}`)}if(!this.options.production){if(o===null)this.tokens.appendCode(", void 0");this.tokens.appendCode(`, ${r}, $\##
{this.getDevSource(e)}, this`)}this.tokens.removeInitialToken();while(!this.tokens.matches1(t.jsxTagEnd))this.tokens\##
.removeToken();this.tokens.replaceToken(")")}transformTagToCreateElement(e){if(this.tokens.replaceToken(this.getCrea\##
teElementInvocationCode()),this.tokens.matches1(t.jsxTagEnd))this.tokens.replaceToken(`${this.getFragmentCode()}, nu\##
ll`),this.processChildren(!0);else if(this.processTagIntro(),this.processPropsObjectWithDevInfo(e),this.tokens.match\##
es2(t.slash,t.jsxTagEnd));else if(this.tokens.matches1(t.jsxTagEnd))this.tokens.removeToken(),this.processChildren(!\##
0);else throw Error("Expected either /> or > at the end of the tag.");this.tokens.removeInitialToken();while(!this.t\##
okens.matches1(t.jsxTagEnd))this.tokens.removeToken();this.tokens.replaceToken(")")}getJSXFuncInvocationCode(e){if(t\##
his.options.production)if(e)return this.claimAutoImportedFuncInvocation("jsxs","/jsx-runtime");else return this.clai\##
mAutoImportedFuncInvocation("jsx","/jsx-runtime");else return this.claimAutoImportedFuncInvocation("jsxDEV","/jsx-de\##
v-runtime")}getCreateElementInvocationCode(){if(this.isAutomaticRuntime)return this.claimAutoImportedFuncInvocation(\##
"createElement","");else{let{jsxPragmaInfo:e}=this;return`${this.importProcessor?this.importProcessor.getIdentifierR\##
eplacement(e.base)||e.base:e.base}${e.suffix}(`}}getFragmentCode(){if(this.isAutomaticRuntime)return this.claimAutoI\##
mportedName("Fragment",this.options.production?"/jsx-runtime":"/jsx-dev-runtime");else{let{jsxPragmaInfo:e}=this;ret\##
urn(this.importProcessor?this.importProcessor.getIdentifierReplacement(e.fragmentBase)||e.fragmentBase:e.fragmentBas\##
e)+e.fragmentSuffix}}claimAutoImportedFuncInvocation(e,s){let r=this.claimAutoImportedName(e,s);if(this.importProces\##
sor)return`${r}.call(void 0, `;else return`${r}(`}claimAutoImportedName(e,s){if(this.importProcessor){let r=this.jsx\##
ImportSource+s;if(!this.cjsAutomaticModuleNameResolutions[r])this.cjsAutomaticModuleNameResolutions[r]=this.importPr\##
ocessor.getFreeIdentifierForPath(r);return`${this.cjsAutomaticModuleNameResolutions[r]}.${e}`}else{if(!this.esmAutom\##
aticImportNameResolutions[e])this.esmAutomaticImportNameResolutions[e]=this.nameManager.claimFreeName(`_${e}`);retur\##
n this.esmAutomaticImportNameResolutions[e]}}processTagIntro(){let e=this.tokens.currentIndex()+1;while(this.tokens.\##
tokens[e].isType||!this.tokens.matches2AtIndex(e-1,t.jsxName,t.jsxName)&&!this.tokens.matches2AtIndex(e-1,t.greaterT\##
han,t.jsxName)&&!this.tokens.matches1AtIndex(e,t.braceL)&&!this.tokens.matches1AtIndex(e,t.jsxTagEnd)&&!this.tokens.\##
matches2AtIndex(e,t.slash,t.jsxTagEnd))e++;if(e===this.tokens.currentIndex()+1){let s=this.tokens.identifierName();i\##
f(Xn(s))this.tokens.replaceToken(`'${s}'`)}while(this.tokens.currentIndex()<e)this.rootTransformer.processToken()}pr\##
ocessPropsObjectWithDevInfo(e){let s=this.options.production?"":`__self: this, __source: ${this.getDevSource(e)}`;if\##
(!this.tokens.matches1(t.jsxName)&&!this.tokens.matches1(t.braceL)){if(s)this.tokens.appendCode(`, {${s}}`);else thi\##
s.tokens.appendCode(", null");return}if(this.tokens.appendCode(", {"),this.processProps(!1),s)this.tokens.appendCode\##
(` ${s}}`);else this.tokens.appendCode("}")}processProps(e){let s=null;while(!0){if(this.tokens.matches2(t.jsxName,t\##
.eq)){let r=this.tokens.identifierName();if(e&&r==="key"){if(s!==null)this.tokens.appendCode(s.replace(/[^\n]/g,""))\##
;this.tokens.removeToken(),this.tokens.removeToken();let o=this.tokens.snapshot();this.processPropValue(),s=this.tok\##
ens.dangerouslyGetAndRemoveCodeSinceSnapshot(o);continue}else this.processPropName(r),this.tokens.replaceToken(": ")\##
,this.processPropValue()}else if(this.tokens.matches1(t.jsxName)){let r=this.tokens.identifierName();this.processPro\##
pName(r),this.tokens.appendCode(": true")}else if(this.tokens.matches1(t.braceL))this.tokens.replaceToken(""),this.r\##
ootTransformer.processBalancedCode(),this.tokens.replaceToken("");else break;this.tokens.appendCode(",")}return s}pr\##
ocessPropName(e){if(e.includes("-"))this.tokens.replaceToken(`'${e}'`);else this.tokens.copyToken()}processPropValue\##
(){if(this.tokens.matches1(t.braceL))this.tokens.replaceToken(""),this.rootTransformer.processBalancedCode(),this.to\##
kens.replaceToken("");else if(this.tokens.matches1(t.jsxTagStart))this.processJSXTag();else this.processStringPropVa\##
lue()}processStringPropValue(){let e=this.tokens.currentToken(),s=this.tokens.code.slice(e.start+1,e.end-1),r=rr(s),\##
o=Gi(s);this.tokens.replaceToken(o+r)}processAutomaticChildrenAndEndProps(e){if(e===oe.StaticChildren)this.tokens.ap\##
pendCode(" children: ["),this.processChildren(!1),this.tokens.appendCode("]}");else{if(e===oe.OneChild)this.tokens.a\##
ppendCode(" children: ");this.processChildren(!1),this.tokens.appendCode("}")}}processChildren(e){let s=e;while(!0){\##
if(this.tokens.matches2(t.jsxTagStart,t.slash))return;let r=!1;if(this.tokens.matches1(t.braceL))if(this.tokens.matc\##
hes2(t.braceL,t.braceR))this.tokens.replaceToken(""),this.tokens.replaceToken("");else this.tokens.replaceToken(s?",\##
 ":""),this.rootTransformer.processBalancedCode(),this.tokens.replaceToken(""),r=!0;else if(this.tokens.matches1(t.j\##
sxTagStart))this.tokens.appendCode(s?", ":""),this.processJSXTag(),r=!0;else if(this.tokens.matches1(t.jsxText)||thi\##
s.tokens.matches1(t.jsxEmptyText))r=this.processChildTextElement(s);else throw Error("Unexpected token when processi\##
ng JSX children.");if(r)s=!0}}processChildTextElement(e){let s=this.tokens.currentToken(),r=this.tokens.code.slice(s\##
.start,s.end),o=rr(r),a=Vi(r);if(a==='""')return this.tokens.replaceToken(o),!1;else return this.tokens.replaceToken\##
(`${e?", ":""}${a}${o}`),!0}getDevSource(e){return`{fileName: ${this.getFilenameVarName()}, ${e}}`}getFilenameVarNam\##
e(){if(!this.filenameVarName)this.filenameVarName=this.nameManager.claimFreeName("_jsxFileName");return this.filenam\##
eVarName}}function Xn(e){let s=e.charCodeAt(0);return s>=l.lowercaseA&&s<=l.lowercaseZ}function Vi(e){let s="",r="",\##
o=!1,a=!1;for(let u=0;u<e.length;u++){let m=e[u];if(m===" "||m==="\t"||m==="\r"){if(!o)r+=m}else if(m===`
`)r="",o=!0;else{if(a&&o)s+=" ";if(s+=r,r="",m==="&"){let{entity:x,newI:k}=or(e,u+1);u=k-1,s+=x}else s+=m;a=!0,o=!1}\##
}if(!o)s+=r;return JSON.stringify(s)}function rr(e){let s=0,r=0;for(let o of e)if(o===`
`)s++,r=0;else if(o===" ")r++;return`
`.repeat(s)+" ".repeat(r)}function Gi(e){let s="";for(let r=0;r<e.length;r++){let o=e[r];if(o===`
`)if(/\s/.test(e[r+1])){s+=" ";while(r<e.length&&/\s/.test(e[r+1]))r++}else s+=`
`;else if(o==="&"){let{entity:a,newI:u}=or(e,r+1);s+=a,r=u-1}else s+=o}return JSON.stringify(s)}function or(e,s){let\##
 r="",o=0,a,u=s;if(e[u]==="#"){let m=10;u++;let x;if(e[u]==="x"){m=16,u++,x=u;while(u<e.length&&Ji(e.charCodeAt(u)))\##
u++}else{x=u;while(u<e.length&&Xi(e.charCodeAt(u)))u++}if(e[u]===";"){let k=e.slice(x,u);if(k)u++,a=String.fromCodeP\##
oint(parseInt(k,m))}}else while(u<e.length&&o++<10){let m=e[u];if(u++,m===";"){a=sr.get(r);break}r+=m}if(!a)return{e\##
ntity:"&",newI:s};return{entity:a,newI:u}}function Xi(e){return e>=l.digit0&&e<=l.digit9}function Ji(e){return e>=l.\##
digit0&&e<=l.digit9||e>=l.lowercaseA&&e<=l.lowercaseF||e>=l.uppercaseA&&e<=l.uppercaseF}function Wt(e,s){let r=mt(s)\##
,o=new Set;for(let a=0;a<e.tokens.length;a++){let u=e.tokens[a];if(u.type===t.name&&!u.isType&&(u.identifierRole===_\##
.Access||u.identifierRole===_.ObjectShorthand||u.identifierRole===_.ExportAccess)&&!u.shadowsGlobal)o.add(e.identifi\##
erNameForToken(u));if(u.type===t.jsxTagStart)o.add(r.base);if(u.type===t.jsxTagStart&&a+1<e.tokens.length&&e.tokens[\##
a+1].type===t.jsxTagEnd)o.add(r.base),o.add(r.fragmentBase);if(u.type===t.jsxName&&u.identifierRole===_.Access){let \##
m=e.identifierNameForToken(u);if(!Xn(m)||e.tokens[a+1].type===t.dot)o.add(e.identifierNameForToken(u))}}return o}cla\##
ss ye{__init(){this.nonTypeIdentifiers=new Set}__init2(){this.importInfoByPath=new Map}__init3(){this.importsToRepla\##
ce=new Map}__init4(){this.identifierReplacements=new Map}__init5(){this.exportBindingsByLocalName=new Map}constructo\##
r(e,s,r,o,a,u,m){this.nameManager=e,this.tokens=s,this.enableLegacyTypeScriptModuleInterop=r,this.options=o,this.isT\##
ypeScriptTransformEnabled=a,this.keepUnusedImports=u,this.helperManager=m,ye.prototype.__init.call(this),ye.prototyp\##
e.__init2.call(this),ye.prototype.__init3.call(this),ye.prototype.__init4.call(this),ye.prototype.__init5.call(this)\##
}preprocessTokens(){for(let e=0;e<this.tokens.tokens.length;e++){if(this.tokens.matches1AtIndex(e,t._import)&&!this.\##
tokens.matches3AtIndex(e,t._import,t.name,t.eq))this.preprocessImportAtIndex(e);if(this.tokens.matches1AtIndex(e,t._\##
export)&&!this.tokens.matches2AtIndex(e,t._export,t.eq))this.preprocessExportAtIndex(e)}this.generateImportReplaceme\##
nts()}pruneTypeOnlyImports(){this.nonTypeIdentifiers=Wt(this.tokens,this.options);for(let[e,s]of this.importInfoByPa\##
th.entries()){if(s.hasBareImport||s.hasStarExport||s.exportStarNames.length>0||s.namedExports.length>0)continue;if([\##
...s.defaultNames,...s.wildcardNames,...s.namedImports.map(({localName:o})=>o)].every((o)=>this.shouldAutomaticallyE\##
lideImportedName(o)))this.importsToReplace.set(e,"")}}shouldAutomaticallyElideImportedName(e){return this.isTypeScri\##
ptTransformEnabled&&!this.keepUnusedImports&&!this.nonTypeIdentifiers.has(e)}generateImportReplacements(){for(let[e,\##
s]of this.importInfoByPath.entries()){let{defaultNames:r,wildcardNames:o,namedImports:a,namedExports:u,exportStarNam\##
es:m,hasStarExport:x}=s;if(r.length===0&&o.length===0&&a.length===0&&u.length===0&&m.length===0&&!x){this.importsToR\##
eplace.set(e,`require('${e}');`);continue}let k=this.getFreeIdentifierForPath(e),T;if(this.enableLegacyTypeScriptMod\##
uleInterop)T=k;else T=o.length>0?o[0]:this.getFreeIdentifierForPath(e);let y=`var ${k} = require('${e}');`;if(o.leng\##
th>0)for(let C of o){let L=this.enableLegacyTypeScriptModuleInterop?k:`${this.helperManager.getHelperName("interopRe\##
quireWildcard")}(${k})`;y+=` var ${C} = ${L};`}else if(m.length>0&&T!==k)y+=` var ${T} = ${this.helperManager.getHel\##
perName("interopRequireWildcard")}(${k});`;else if(r.length>0&&T!==k)y+=` var ${T} = ${this.helperManager.getHelperN\##
ame("interopRequireDefault")}(${k});`;for(let{importedName:C,localName:L}of u)y+=` ${this.helperManager.getHelperNam\##
e("createNamedExportFrom")}(${k}, '${L}', '${C}');`;for(let C of m)y+=` exports.${C} = ${T};`;if(x)y+=` ${this.helpe\##
rManager.getHelperName("createStarExport")}(${k});`;this.importsToReplace.set(e,y);for(let C of r)this.identifierRep\##
lacements.set(C,`${T}.default`);for(let{importedName:C,localName:L}of a)this.identifierReplacements.set(L,`${k}.${C}\##
`)}}getFreeIdentifierForPath(e){let s=e.split("/"),o=s[s.length-1].replace(/\W/g,"");return this.nameManager.claimFr\##
eeName(`_${o}`)}preprocessImportAtIndex(e){let s=[],r=[],o=[];if(e++,(this.tokens.matchesContextualAtIndex(e,c._type\##
)||this.tokens.matches1AtIndex(e,t._typeof))&&!this.tokens.matches1AtIndex(e+1,t.comma)&&!this.tokens.matchesContext\##
ualAtIndex(e+1,c._from))return;if(this.tokens.matches1AtIndex(e,t.parenL))return;if(this.tokens.matches1AtIndex(e,t.\##
name)){if(s.push(this.tokens.identifierNameAtIndex(e)),e++,this.tokens.matches1AtIndex(e,t.comma))e++}if(this.tokens\##
.matches1AtIndex(e,t.star))e+=2,r.push(this.tokens.identifierNameAtIndex(e)),e++;if(this.tokens.matches1AtIndex(e,t.\##
braceL)){let m=this.getNamedImports(e+1);e=m.newIndex;for(let x of m.namedImports)if(x.importedName==="default")s.pu\##
sh(x.localName);else o.push(x)}if(this.tokens.matchesContextualAtIndex(e,c._from))e++;if(!this.tokens.matches1AtInde\##
x(e,t.string))throw Error("Expected string token at the end of import statement.");let a=this.tokens.stringValueAtIn\##
dex(e),u=this.getImportInfo(a);if(u.defaultNames.push(...s),u.wildcardNames.push(...r),u.namedImports.push(...o),s.l\##
ength===0&&r.length===0&&o.length===0)u.hasBareImport=!0}preprocessExportAtIndex(e){if(this.tokens.matches2AtIndex(e\##
,t._export,t._var)||this.tokens.matches2AtIndex(e,t._export,t._let)||this.tokens.matches2AtIndex(e,t._export,t._cons\##
t))this.preprocessVarExportAtIndex(e);else if(this.tokens.matches2AtIndex(e,t._export,t._function)||this.tokens.matc\##
hes2AtIndex(e,t._export,t._class)){let s=this.tokens.identifierNameAtIndex(e+2);this.addExportBinding(s,s)}else if(t\##
his.tokens.matches3AtIndex(e,t._export,t.name,t._function)){let s=this.tokens.identifierNameAtIndex(e+3);this.addExp\##
ortBinding(s,s)}else if(this.tokens.matches2AtIndex(e,t._export,t.braceL))this.preprocessNamedExportAtIndex(e);else \##
if(this.tokens.matches2AtIndex(e,t._export,t.star))this.preprocessExportStarAtIndex(e)}preprocessVarExportAtIndex(e)\##
{let s=0;for(let r=e+2;;r++)if(this.tokens.matches1AtIndex(r,t.braceL)||this.tokens.matches1AtIndex(r,t.dollarBraceL\##
)||this.tokens.matches1AtIndex(r,t.bracketL))s++;else if(this.tokens.matches1AtIndex(r,t.braceR)||this.tokens.matche\##
s1AtIndex(r,t.bracketR))s--;else if(s===0&&!this.tokens.matches1AtIndex(r,t.name))break;else if(this.tokens.matches1\##
AtIndex(1,t.eq)){let o=this.tokens.currentToken().rhsEndIndex;if(o==null)throw Error("Expected = token with an end i\##
ndex.");r=o-1}else{let o=this.tokens.tokens[r];if(jt(o)){let a=this.tokens.identifierNameAtIndex(r);this.identifierR\##
eplacements.set(a,`exports.${a}`)}}}preprocessNamedExportAtIndex(e){e+=2;let{newIndex:s,namedImports:r}=this.getName\##
dImports(e);if(e=s,this.tokens.matchesContextualAtIndex(e,c._from))e++;else{for(let{importedName:u,localName:m}of r)\##
this.addExportBinding(u,m);return}if(!this.tokens.matches1AtIndex(e,t.string))throw Error("Expected string token at \##
the end of import statement.");let o=this.tokens.stringValueAtIndex(e);this.getImportInfo(o).namedExports.push(...r)\##
}preprocessExportStarAtIndex(e){let s=null;if(this.tokens.matches3AtIndex(e,t._export,t.star,t._as))e+=3,s=this.toke\##
ns.identifierNameAtIndex(e),e+=2;else e+=3;if(!this.tokens.matches1AtIndex(e,t.string))throw Error("Expected string \##
token at the end of star export statement.");let r=this.tokens.stringValueAtIndex(e),o=this.getImportInfo(r);if(s!==\##
null)o.exportStarNames.push(s);else o.hasStarExport=!0}getNamedImports(e){let s=[];while(!0){if(this.tokens.matches1\##
AtIndex(e,t.braceR)){e++;break}let r=ke(this.tokens,e);if(e=r.endIndex,!r.isType)s.push({importedName:r.leftName,loc\##
alName:r.rightName});if(this.tokens.matches2AtIndex(e,t.comma,t.braceR)){e+=2;break}else if(this.tokens.matches1AtIn\##
dex(e,t.braceR)){e++;break}else if(this.tokens.matches1AtIndex(e,t.comma))e++;else throw Error(`Unexpected token: ${\##
JSON.stringify(this.tokens.tokens[e])}`)}return{newIndex:e,namedImports:s}}getImportInfo(e){let s=this.importInfoByP\##
ath.get(e);if(s)return s;let r={defaultNames:[],wildcardNames:[],namedImports:[],namedExports:[],hasBareImport:!1,ex\##
portStarNames:[],hasStarExport:!1};return this.importInfoByPath.set(e,r),r}addExportBinding(e,s){if(!this.exportBind\##
ingsByLocalName.has(e))this.exportBindingsByLocalName.set(e,[]);this.exportBindingsByLocalName.get(e).push(s)}claimI\##
mportCode(e){let s=this.importsToReplace.get(e);return this.importsToReplace.set(e,""),s||""}getIdentifierReplacemen\##
t(e){return this.identifierReplacements.get(e)||null}resolveExportBinding(e){let s=this.exportBindingsByLocalName.ge\##
t(e);if(!s||s.length===0)return null;return s.map((r)=>`exports.${r}`).join(" = ")}getGlobalNames(){return new Set([\##
...this.identifierReplacements.keys(),...this.exportBindingsByLocalName.keys()])}}var zi=44,Ki=59,ir="ABCDEFGHIJKLMN\##
OPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",lr=new Uint8Array(64),Yi=new Uint8Array(128);for(let e=0;e<ir.le\##
ngth;e++){let s=ir.charCodeAt(e);lr[e]=s,Yi[s]=e}function dt(e,s){do{let r=s&31;if(s>>>=5,s>0)r|=32;e.write(lr[r])}w\##
hile(s>0)}function kt(e){return e<0?-e<<1|1:e<<1}var ar=16384,cr=typeof TextDecoder<"u"?new TextDecoder:typeof Buffe\##
r<"u"?{decode(e){return Buffer.from(e.buffer,e.byteOffset,e.byteLength).toString()}}:{decode(e){let s="";for(let r=0\##
;r<e.length;r++)s+=String.fromCharCode(e[r]);return s}},Qi=class{constructor(){this.pos=0,this.out="",this.buffer=ne\##
w Uint8Array(ar)}write(e){let{buffer:s}=this;if(s[this.pos++]=e,this.pos===ar)this.out+=cr.decode(s),this.pos=0}flus\##
h(){let{buffer:e,out:s,pos:r}=this;return r>0?s+cr.decode(e.subarray(0,r)):s}};function Jn(e){let s=new Qi,r=0,o=0,a\##
=0,u=0;for(let m=0;m<e.length;m++){let x=e[m];if(m>0)s.write(Ki);if(x.length===0)continue;let k=0;for(let T=0;T<x.le\##
ngth;T++){let y=x[T];if(T>0)s.write(zi);if(dt(s,kt(y[0]-k)),k=y[0],y.length===1)continue;if(dt(s,kt(y[1]-r)),dt(s,kt\##
(y[2]-o)),dt(s,kt(y[3]-a)),r=y[1],o=y[2],a=y[3],y.length===4)continue;dt(s,kt(y[4]-u)),u=y[4]}}return s.flush()}var \##
Zi=$1(ur(),1);var Yn=class{constructor(){this._indexes={__proto__:null},this.array=[]}};function mr(e){return e}func\##
tion ea(e,s){return mr(e)._indexes[s]}function pr(e,s){let r=ea(e,s);if(r!==void 0)return r;let{array:o,_indexes:a}=\##
mr(e),u=o.push(s);return a[s]=u-1}var ta=0,sa=1,na=2,ra=3,oa=4,dr=-1,kr=class{constructor({file:e,sourceRoot:s}={}){\##
this._names=new Yn,this._sources=new Yn,this._sourcesContent=[],this._mappings=[],this.file=e,this.sourceRoot=s,this\##
._ignoreList=new Yn}};function xr(e){return e}var Vt=(e,s,r,o,a,u,m,x)=>aa(!0,e,s,r,o,a,u,m,x);function ia(e){let{_m\##
appings:s,_sources:r,_sourcesContent:o,_names:a,_ignoreList:u}=xr(e);return ua(s),{version:3,file:e.file||void 0,nam\##
es:a.array,sourceRoot:e.sourceRoot||void 0,sources:r.array,sourcesContent:o,mappings:s,ignoreList:u.array}}function \##
gr(e){let s=ia(e);return Object.assign({},s,{mappings:Jn(s.mappings)})}function aa(e,s,r,o,a,u,m,x,k){let{_mappings:\##
T,_sources:y,_sourcesContent:C,_names:L}=xr(s),M=ca(T,r),z=la(M,o);if(!a){if(e&&pa(M,z))return;return hr(M,z,[o])}fr\##
(u),fr(m);let U=pr(y,a),I=x?pr(L,x):dr;if(U===C.length)C[U]=k!=null?k:null;if(e&&fa(M,z,U,u,m,I))return;return hr(M,\##
z,x?[o,U,u,m,I]:[o,U,u,m])}function fr(e){}function ca(e,s){for(let r=e.length;r<=s;r++)e[r]=[];return e[s]}function\##
 la(e,s){let r=e.length;for(let o=r-1;o>=0;r=o--){let a=e[o];if(s>=a[ta])break}return r}function hr(e,s,r){for(let o\##
=e.length;o>s;o--)e[o]=e[o-1];e[s]=r}function ua(e){let{length:s}=e,r=s;for(let o=r-1;o>=0;r=o,o--)if(e[o].length>0)\##
break;if(r<s)e.length=r}function pa(e,s){if(s===0)return!0;return e[s-1].length===1}function fa(e,s,r,o,a,u){if(s===\##
0)return!1;let m=e[s-1];if(m.length===1)return!1;return r===m[sa]&&o===m[na]&&a===m[ra]&&u===(m.length===5?m[oa]:dr)\##
}function Qn({code:e,mappings:s},r,o,a,u){let m=ha(a,u),x=new kr({file:o.compiledFilename}),k=0,T=s[0];while(T===voi\##
d 0&&k<s.length-1)k++,T=s[k];let y=0,C=0;if(T!==C)Vt(x,y,0,r,y,0);for(let U=0;U<e.length;U++){if(U===T){let I=T-C,N=\##
m[k];Vt(x,y,I,r,y,N);while((T===U||T===void 0)&&k<s.length-1)k++,T=s[k]}if(e.charCodeAt(U)===l.lineFeed){if(y++,C=U+\##
1,T!==C)Vt(x,y,0,r,y,0)}}let{sourceRoot:L,sourcesContent:M,...z}=gr(x);return z}function ha(e,s){let r=Array(s.lengt\##
h),o=0,a=s[o].start,u=0;for(let m=0;m<e.length;m++){if(m===a)r[o]=a-u,o++,a=s[o].start;if(e.charCodeAt(m)===l.lineFe\##
ed)u=m+1}return r}var ma={require:`
    import {createRequire as CREATE_REQUIRE_NAME} from "module";
    const require = CREATE_REQUIRE_NAME(import.meta.url);
  `,interopRequireWildcard:`
    function interopRequireWildcard(obj) {
      if (obj && obj.__esModule) {
        return obj;
      } else {
        var newObj = {};
        if (obj != null) {
          for (var key in obj) {
            if (Object.prototype.hasOwnProperty.call(obj, key)) {
              newObj[key] = obj[key];
            }
          }
        }
        newObj.default = obj;
        return newObj;
      }
    }
  `,interopRequireDefault:`
    function interopRequireDefault(obj) {
      return obj && obj.__esModule ? obj : { default: obj };
    }
  `,createNamedExportFrom:`
    function createNamedExportFrom(obj, localName, importedName) {
      Object.defineProperty(exports, localName, {enumerable: true, configurable: true, get: () => obj[importedName]}\##
);
    }
  `,createStarExport:`
    function createStarExport(obj) {
      Object.keys(obj)
        .filter((key) => key !== "default" && key !== "__esModule")
        .forEach((key) => {
          if (exports.hasOwnProperty(key)) {
            return;
          }
          Object.defineProperty(exports, key, {enumerable: true, configurable: true, get: () => obj[key]});
        });
    }
  `,nullishCoalesce:`
    function nullishCoalesce(lhs, rhsFn) {
      if (lhs != null) {
        return lhs;
      } else {
        return rhsFn();
      }
    }
  `,asyncNullishCoalesce:`
    async function asyncNullishCoalesce(lhs, rhsFn) {
      if (lhs != null) {
        return lhs;
      } else {
        return await rhsFn();
      }
    }
  `,optionalChain:`
    function optionalChain(ops) {
      let lastAccessLHS = undefined;
      let value = ops[0];
      let i = 1;
      while (i < ops.length) {
        const op = ops[i];
        const fn = ops[i + 1];
        i += 2;
        if ((op === 'optionalAccess' || op === 'optionalCall') && value == null) {
          return undefined;
        }
        if (op === 'access' || op === 'optionalAccess') {
          lastAccessLHS = value;
          value = fn(value);
        } else if (op === 'call' || op === 'optionalCall') {
          value = fn((...args) => value.call(lastAccessLHS, ...args));
          lastAccessLHS = undefined;
        }
      }
      return value;
    }
  `,asyncOptionalChain:`
    async function asyncOptionalChain(ops) {
      let lastAccessLHS = undefined;
      let value = ops[0];
      let i = 1;
      while (i < ops.length) {
        const op = ops[i];
        const fn = ops[i + 1];
        i += 2;
        if ((op === 'optionalAccess' || op === 'optionalCall') && value == null) {
          return undefined;
        }
        if (op === 'access' || op === 'optionalAccess') {
          lastAccessLHS = value;
          value = await fn(value);
        } else if (op === 'call' || op === 'optionalCall') {
          value = await fn((...args) => value.call(lastAccessLHS, ...args));
          lastAccessLHS = undefined;
        }
      }
      return value;
    }
  `,optionalChainDelete:`
    function optionalChainDelete(ops) {
      const result = OPTIONAL_CHAIN_NAME(ops);
      return result == null ? true : result;
    }
  `,asyncOptionalChainDelete:`
    async function asyncOptionalChainDelete(ops) {
      const result = await ASYNC_OPTIONAL_CHAIN_NAME(ops);
      return result == null ? true : result;
    }
  `};class xt{__init(){this.helperNames={}}__init2(){this.createRequireName=null}constructor(e){this.nameManager=e,x\##
t.prototype.__init.call(this),xt.prototype.__init2.call(this)}getHelperName(e){let s=this.helperNames[e];if(s)return\##
 s;return s=this.nameManager.claimFreeName(`_${e}`),this.helperNames[e]=s,s}emitHelpers(){let e="";if(this.helperNam\##
es.optionalChainDelete)this.getHelperName("optionalChain");if(this.helperNames.asyncOptionalChainDelete)this.getHelp\##
erName("asyncOptionalChain");for(let[s,r]of Object.entries(ma)){let o=this.helperNames[s],a=r;if(s==="optionalChainD\##
elete")a=a.replace("OPTIONAL_CHAIN_NAME",this.helperNames.optionalChain);else if(s==="asyncOptionalChainDelete")a=a.\##
replace("ASYNC_OPTIONAL_CHAIN_NAME",this.helperNames.asyncOptionalChain);else if(s==="require"){if(this.createRequir\##
eName===null)this.createRequireName=this.nameManager.claimFreeName("_createRequire");a=a.replace(/CREATE_REQUIRE_NAM\##
E/g,this.createRequireName)}if(o)e+=" ",e+=a.replace(s,o).replace(/\s+/g," ").trim()}return e}}function Gt(e,s,r){if\##
(!da(e,r))return;ka(e,s,r)}function da(e,s){for(let r of e.tokens)if(r.type===t.name&&!r.isType&&J1(r)&&s.has(e.iden\##
tifierNameForToken(r)))return!0;return!1}function ka(e,s,r){let o=[],a=s.length-1;for(let u=e.tokens.length-1;;u--){\##
while(o.length>0&&o[o.length-1].startTokenIndex===u+1)o.pop();while(a>=0&&s[a].endTokenIndex===u+1)o.push(s[a]),a--;\##
if(u<0)break;let m=e.tokens[u],x=e.identifierNameForToken(m);if(o.length>1&&!m.isType&&m.type===t.name&&r.has(x)){if\##
(z1(m))_r(o[o.length-1],e,x);else if(K1(m)){let k=o.length-1;while(k>0&&!o[k].isFunctionScope)k--;if(k<0)throw Error\##
("Did not find parent function scope.");_r(o[k],e,x)}}}if(o.length>0)throw Error("Expected empty scope stack after p\##
rocessing file.")}function _r(e,s,r){for(let o=e.startTokenIndex;o<e.endTokenIndex;o++){let a=s.tokens[o];if((a.type\##
===t.name||a.type===t.jsxName)&&s.identifierNameForToken(a)===r)a.shadowsGlobal=!0}}function Zn(e,s){let r=[];for(le\##
t o of s)if(o.type===t.name)r.push(e.slice(o.start,o.end));return r}class gt{__init(){this.usedNames=new Set}constru\##
ctor(e,s){gt.prototype.__init.call(this),this.usedNames=new Set(Zn(e,s))}claimFreeName(e){let s=this.findFreeName(e)\##
;return this.usedNames.add(s),s}findFreeName(e){if(!this.usedNames.has(e))return e;let s=2;while(this.usedNames.has(\##
e+String(s)))s++;return e+String(s)}}function Ir(){}function e1(){h(),X(!1)}function t1(e){h(),It(e)}function he(e){\##
b(),Xt(e)}function st(){b(),n.tokens[n.tokens.length-1].identifierRole=_.ImportDeclaration}function Xt(e){let s;if(n\##
.scopeDepth===0)s=_.TopLevelDeclaration;else if(e)s=_.BlockScopedDeclaration;else s=_.FunctionScopedDeclaration;n.to\##
kens[n.tokens.length-1].identifierRole=s}function It(e){switch(n.type){case t._this:{let s=A(0);h(),E(s);return}case\##
 t._yield:case t.name:{n.type=t.name,he(e);return}case t.bracketL:{h(),yt(t.bracketR,e,!0);return}case t.braceL:bt(!\##
0,e);return;default:w()}}function yt(e,s,r=!1,o=!1,a=0){let u=!0,m=!1,x=n.tokens.length;while(!p(e)&&!n.error){if(u)\##
u=!1;else if(f(t.comma),n.tokens[n.tokens.length-1].contextId=a,!m&&n.tokens[x].isType)n.tokens[n.tokens.length-1].i\##
sType=!0,m=!0;if(r&&i(t.comma));else if(p(e))break;else if(i(t.ellipsis)){t1(s),yr(),p(t.comma),f(e);break}else xa(o\##
,s)}}function xa(e,s){if(e)Tt([c._public,c._protected,c._private,c._readonly,c._override]);_t(s),yr(),_t(s,!0)}funct\##
ion yr(){if(v)br();else if(R)Tr()}function _t(e,s=!1){if(!s)It(e);if(!p(t.eq))return;let r=n.tokens.length-1;X(),n.t\##
okens[r].rhsEndIndex=n.tokens.length}function n1(){return i(t.name)}function ga(){return i(t.name)||Boolean(n.type&t\##
.IS_KEYWORD)||i(t.string)||i(t.num)||i(t.bigint)||i(t.decimal)}function Nr(){let e=n.snapshot();if(h(),(i(t.bracketL\##
)||i(t.braceL)||i(t.star)||i(t.ellipsis)||i(t.hash)||ga())&&!K())return!0;else return n.restoreFromSnapshot(e),!1}fu\##
nction Tt(e){while(!0)if(Pr(e)===null)break}function Pr(e){if(!i(t.name))return null;let s=n.contextualKeyword;if(e.\##
indexOf(s)!==-1&&Nr()){switch(s){case c._readonly:n.tokens[n.tokens.length-1].type=t._readonly;break;case c._abstrac\##
t:n.tokens[n.tokens.length-1].type=t._abstract;break;case c._static:n.tokens[n.tokens.length-1].type=t._static;break\##
;case c._public:n.tokens[n.tokens.length-1].type=t._public;break;case c._private:n.tokens[n.tokens.length-1].type=t.\##
_private;break;case c._protected:n.tokens[n.tokens.length-1].type=t._protected;break;case c._override:n.tokens[n.tok\##
ens.length-1].type=t._override;break;case c._declare:n.tokens[n.tokens.length-1].type=t._declare;break;default:break\##
}return s}return null}function St(){b();while(p(t.dot))b()}function _a(){if(St(),!K()&&i(t.lessThan))ot()}function I\##
a(){h(),rt()}function ya(){h()}function Ta(){if(f(t._typeof),i(t._import))Rr();else St();if(!K()&&i(t.lessThan))ot()\##
}function Rr(){if(f(t._import),f(t.parenL),f(t.string),f(t.parenR),p(t.dot))St();if(i(t.lessThan))ot()}function ba()\##
{p(t._const);let e=p(t._in),s=V(c._out);if(p(t._const),(e||s)&&!i(t.name))n.tokens[n.tokens.length-1].type=t.name;el\##
se b();if(p(t._extends))H();if(p(t.eq))H()}function Pe(){if(i(t.lessThan))zt()}function zt(){let e=A(0);if(i(t.lessT\##
han)||i(t.typeParameterStart))h();else w();while(!p(t.greaterThan)&&!n.error)ba(),p(t.comma);E(e)}function i1(e){let\##
 s=e===t.arrow;if(Pe(),f(t.parenL),n.scopeDepth++,wa(!1),n.scopeDepth--,s)wt(e);else if(i(e))wt(e)}function wa(e){yt\##
(t.parenR,e)}function Jt(){if(!p(t.comma))F()}function wr(){i1(t.colon),Jt()}function Sa(){let e=n.snapshot();h();le\##
t s=p(t.name)&&i(t.colon);return n.restoreFromSnapshot(e),s}function vr(){if(!(i(t.bracketL)&&Sa()))return!1;let e=A\##
(0);return f(t.bracketL),b(),rt(),f(t.bracketR),ve(),Jt(),E(e),!0}function Sr(e){if(p(t.question),!e&&(i(t.parenL)||\##
i(t.lessThan)))i1(t.colon),Jt();else ve(),Jt()}function Ea(){if(i(t.parenL)||i(t.lessThan)){wr();return}if(i(t._new)\##
){if(h(),i(t.parenL)||i(t.lessThan))wr();else Sr(!1);return}let e=!!Pr([c._readonly]);if(vr())return;if((g(c._get)||\##
g(c._set))&&Nr());Le(-1),Sr(e)}function Aa(){Lr()}function Lr(){f(t.braceL);while(!p(t.braceR)&&!n.error)Ea()}functi\##
on Ca(){let e=n.snapshot(),s=Na();return n.restoreFromSnapshot(e),s}function Na(){if(h(),p(t.plus)||p(t.minus))retur\##
n g(c._readonly);if(g(c._readonly))h();if(!i(t.bracketL))return!1;if(h(),!n1())return!1;return h(),i(t._in)}function\##
 Pa(){b(),f(t._in),H()}function Ra(){if(f(t.braceL),i(t.plus)||i(t.minus))h(),q(c._readonly);else V(c._readonly);if(\##
f(t.bracketL),Pa(),V(c._as))H();if(f(t.bracketR),i(t.plus)||i(t.minus))h(),f(t.question);else p(t.question);Va(),F()\##
,f(t.braceR)}function va(){f(t.bracketL);while(!p(t.bracketR)&&!n.error)La(),p(t.comma)}function La(){if(p(t.ellipsi\##
s))H();else H(),p(t.question);if(p(t.colon))H()}function Da(){f(t.parenL),H(),f(t.parenR)}function Fa(){de(),de();wh\##
ile(!i(t.backQuote)&&!n.error)f(t.dollarBraceL),H(),de(),de();h()}var Ce;(function(e){e[e.TSFunctionType=0]="TSFunct\##
ionType";let r=1;e[e.TSConstructorType=r]="TSConstructorType";let o=r+1;e[e.TSAbstractConstructorType=o]="TSAbstract\##
ConstructorType"})(Ce||(Ce={}));function s1(e){if(e===Ce.TSAbstractConstructorType)q(c._abstract);if(e===Ce.TSConstr\##
uctorType||e===Ce.TSAbstractConstructorType)f(t._new);let s=n.inDisallowConditionalTypesContext;n.inDisallowConditio\##
nalTypesContext=!1,i1(t.arrow),n.inDisallowConditionalTypesContext=s}function Oa(){switch(n.type){case t.name:_a();r\##
eturn;case t._void:case t._null:h();return;case t.string:case t.num:case t.bigint:case t.decimal:case t._true:case t\##
._false:Ne();return;case t.minus:h(),Ne();return;case t._this:{if(ya(),g(c._is)&&!K())Ia();return}case t._typeof:Ta(\##
);return;case t._import:Rr();return;case t.braceL:if(Ca())Ra();else Aa();return;case t.bracketL:va();return;case t.p\##
arenL:Da();return;case t.backQuote:Fa();return;default:if(n.type&t.IS_KEYWORD){h(),n.tokens[n.tokens.length-1].type=\##
t.name;return}break}w()}function Ma(){Oa();while(!K()&&p(t.bracketL))if(!p(t.bracketR))H(),f(t.bracketR)}function Ba\##
(){if(q(c._infer),b(),i(t._extends)){let e=n.snapshot();f(t._extends);let s=n.inDisallowConditionalTypesContext;if(n\##
.inDisallowConditionalTypesContext=!0,H(),n.inDisallowConditionalTypesContext=s,n.error||!n.inDisallowConditionalTyp\##
esContext&&i(t.question))n.restoreFromSnapshot(e)}}function r1(){if(g(c._keyof)||g(c._unique)||g(c._readonly))h(),r1\##
();else if(g(c._infer))Ba();else{let e=n.inDisallowConditionalTypesContext;n.inDisallowConditionalTypesContext=!1,Ma\##
(),n.inDisallowConditionalTypesContext=e}}function Er(){if(p(t.bitwiseAND),r1(),i(t.bitwiseAND))while(p(t.bitwiseAND\##
))r1()}function ja(){if(p(t.bitwiseOR),Er(),i(t.bitwiseOR))while(p(t.bitwiseOR))Er()}function qa(){if(i(t.lessThan))\##
return!0;return i(t.parenL)&&Ha()}function $a(){if(i(t.name)||i(t._this))return h(),!0;if(i(t.braceL)||i(t.bracketL)\##
){let e=1;h();while(e>0&&!n.error){if(i(t.braceL)||i(t.bracketL))e++;else if(i(t.braceR)||i(t.bracketR))e--;h()}retu\##
rn!0}return!1}function Ha(){let e=n.snapshot(),s=Ua();return n.restoreFromSnapshot(e),s}function Ua(){if(h(),i(t.par\##
enR)||i(t.ellipsis))return!0;if($a()){if(i(t.colon)||i(t.comma)||i(t.question)||i(t.eq))return!0;if(i(t.parenR)){if(\##
h(),i(t.arrow))return!0}}return!1}function wt(e){let s=A(0);if(f(e),!Ga())H();E(s)}function Wa(){if(i(t.colon))wt(t.\##
colon)}function ve(){if(i(t.colon))rt()}function Va(){if(p(t.colon))H()}function Ga(){let e=n.snapshot();if(g(c._ass\##
erts))if(h(),V(c._is))return H(),!0;else if(n1()||i(t._this)){if(h(),V(c._is))H();return!0}else return n.restoreFrom\##
Snapshot(e),!1;else if(n1()||i(t._this))if(h(),g(c._is)&&!K())return h(),H(),!0;else return n.restoreFromSnapshot(e)\##
,!1;return!1}function rt(){let e=A(0);f(t.colon),H(),E(e)}function H(){if(Ar(),n.inDisallowConditionalTypesContext||\##
K()||!p(t._extends))return;let e=n.inDisallowConditionalTypesContext;n.inDisallowConditionalTypesContext=!0,Ar(),n.i\##
nDisallowConditionalTypesContext=e,f(t.question),H(),f(t.colon),H()}function Xa(){return g(c._abstract)&&O()===t._ne\##
w}function Ar(){if(qa()){s1(Ce.TSFunctionType);return}if(i(t._new)){s1(Ce.TSConstructorType);return}else if(Xa()){s1\##
(Ce.TSAbstractConstructorType);return}ja()}function Dr(){let e=A(1);H(),f(t.greaterThan),E(e),it()}function Fr(){if(\##
p(t.jsxTagStart)){n.tokens[n.tokens.length-1].type=t.typeParameterStart;let e=A(1);while(!i(t.greaterThan)&&!n.error\##
)H(),p(t.comma);ie(),E(e)}}function Or(){while(!i(t.braceL)&&!n.error)Ja(),p(t.comma)}function Ja(){if(St(),i(t.less\##
Than))ot()}function za(){if(he(!1),Pe(),p(t._extends))Or();Lr()}function Ka(){he(!1),Pe(),f(t.eq),H(),F()}function Y\##
a(){if(i(t.string))Ne();else b();if(p(t.eq)){let e=n.tokens.length-1;X(),n.tokens[e].rhsEndIndex=n.tokens.length}}fu\##
nction a1(){he(!1),f(t.braceL);while(!p(t.braceR)&&!n.error)Ya(),p(t.comma)}function c1(){f(t.braceL),at(t.braceR)}f\##
unction o1(){if(he(!1),p(t.dot))o1();else c1()}function Mr(){if(g(c._global))b();else if(i(t.string))pe();else w();i\##
f(i(t.braceL))c1();else F()}function Kt(){st(),f(t.eq),Za(),F()}function Qa(){return g(c._require)&&O()===t.parenL}f\##
unction Za(){if(Qa())ec();else St()}function ec(){if(q(c._require),f(t.parenL),!i(t.string))w();Ne(),f(t.parenR)}fun\##
ction tc(){if(le())return!1;switch(n.type){case t._function:{let e=A(1);h();let s=n.start;return Te(s,!0),E(e),!0}ca\##
se t._class:{let e=A(1);return we(!0,!1),E(e),!0}case t._const:if(i(t._const)&&et(c._enum)){let e=A(1);return f(t._c\##
onst),q(c._enum),n.tokens[n.tokens.length-1].type=t._enum,a1(),E(e),!0}case t._var:case t._let:{let e=A(1);return At\##
(n.type!==t._var),E(e),!0}case t.name:{let e=A(1),s=n.contextualKeyword,r=!1;if(s===c._global)Mr(),r=!0;else r=Yt(s,\##
!0);return E(e),r}default:return!1}}function Cr(){return Yt(n.contextualKeyword,!0)}function sc(e){switch(e){case c.\##
_declare:{let s=n.tokens.length-1;if(tc())return n.tokens[s].type=t._declare,!0;break}case c._global:if(i(t.braceL))\##
return c1(),!0;break;default:return Yt(e,!1)}return!1}function Yt(e,s){switch(e){case c._abstract:if(nt(s)&&i(t._cla\##
ss))return n.tokens[n.tokens.length-1].type=t._abstract,we(!0,!1),!0;break;case c._enum:if(nt(s)&&i(t.name))return n\##
.tokens[n.tokens.length-1].type=t._enum,a1(),!0;break;case c._interface:if(nt(s)&&i(t.name)){let r=A(s?2:1);return z\##
a(),E(r),!0}break;case c._module:if(nt(s)){if(i(t.string)){let r=A(s?2:1);return Mr(),E(r),!0}else if(i(t.name)){let\##
 r=A(s?2:1);return o1(),E(r),!0}}break;case c._namespace:if(nt(s)&&i(t.name)){let r=A(s?2:1);return o1(),E(r),!0}bre\##
ak;case c._type:if(nt(s)&&i(t.name)){let r=A(s?2:1);return Ka(),E(r),!0}break;default:break}return!1}function nt(e){\##
if(e)return h(),!0;else return!le()}function nc(){let e=n.snapshot();if(zt(),be(),Wa(),f(t.arrow),n.error)return n.r\##
estoreFromSnapshot(e),!1;return De(!0),!0}function l1(){if(n.type===t.bitShiftL)n.pos-=1,S(t.lessThan);ot()}function\##
 ot(){let e=A(0);f(t.lessThan);while(!i(t.greaterThan)&&!n.error)H(),p(t.comma);if(!e)E(e),Ht(),f(t.greaterThan),n.t\##
okens[n.tokens.length-1].isType=!0;else f(t.greaterThan),E(e)}function u1(){if(i(t.name))switch(n.contextualKeyword)\##
{case c._abstract:case c._declare:case c._enum:case c._interface:case c._module:case c._namespace:case c._type:retur\##
n!0;default:break}return!1}function Br(e,s){if(i(t.colon))wt(t.colon);if(!i(t.braceL)&&le()){let r=n.tokens.length-1\##
;while(r>=0&&(n.tokens[r].start>=e||n.tokens[r].type===t._default||n.tokens[r].type===t._export))n.tokens[r].isType=\##
!0,r--;return}De(!1,s)}function jr(e,s,r){if(!K()&&p(t.bang)){n.tokens[n.tokens.length-1].type=t.nonNullAssertion;re\##
turn}if(i(t.lessThan)||i(t.bitShiftL)){let o=n.snapshot();if(!s&&p1()){if(nc())return}if(l1(),!s&&p(t.parenL))n.toke\##
ns[n.tokens.length-1].subscriptStartIndex=e,me();else if(i(t.backQuote))Qt();else if(n.type===t.greaterThan||n.type!\##
==t.parenL&&Boolean(n.type&t.IS_EXPRESSION_START)&&!K())w();if(n.error)n.restoreFromSnapshot(o);else return}else if(\##
!s&&i(t.questionDot)&&O()===t.lessThan)h(),n.tokens[e].isOptionalChainStart=!0,n.tokens[n.tokens.length-1].subscript\##
StartIndex=e,ot(),f(t.parenL),me();Et(e,s,r)}function qr(){if(p(t._import)){if(g(c._type)&&O()!==t.eq)q(c._type);ret\##
urn Kt(),!0}else if(p(t.eq))return J(),F(),!0;else if(V(c._as))return q(c._namespace),b(),F(),!0;else{if(g(c._type))\##
{let e=O();if(e===t.braceL||e===t.star)h()}return!1}}function $r(){if(b(),i(t.comma)||i(t.braceR)){n.tokens[n.tokens\##
.length-1].identifierRole=_.ImportDeclaration;return}if(b(),i(t.comma)||i(t.braceR)){n.tokens[n.tokens.length-1].ide\##
ntifierRole=_.ImportDeclaration,n.tokens[n.tokens.length-2].isType=!0,n.tokens[n.tokens.length-1].isType=!0;return}i\##
f(b(),i(t.comma)||i(t.braceR)){n.tokens[n.tokens.length-3].identifierRole=_.ImportAccess,n.tokens[n.tokens.length-1]\##
.identifierRole=_.ImportDeclaration;return}b(),n.tokens[n.tokens.length-3].identifierRole=_.ImportAccess,n.tokens[n.\##
tokens.length-1].identifierRole=_.ImportDeclaration,n.tokens[n.tokens.length-4].isType=!0,n.tokens[n.tokens.length-3\##
].isType=!0,n.tokens[n.tokens.length-2].isType=!0,n.tokens[n.tokens.length-1].isType=!0}function Hr(){if(b(),i(t.com\##
ma)||i(t.braceR)){n.tokens[n.tokens.length-1].identifierRole=_.ExportAccess;return}if(b(),i(t.comma)||i(t.braceR)){n\##
.tokens[n.tokens.length-1].identifierRole=_.ExportAccess,n.tokens[n.tokens.length-2].isType=!0,n.tokens[n.tokens.len\##
gth-1].isType=!0;return}if(b(),i(t.comma)||i(t.braceR)){n.tokens[n.tokens.length-3].identifierRole=_.ExportAccess;re\##
turn}b(),n.tokens[n.tokens.length-3].identifierRole=_.ExportAccess,n.tokens[n.tokens.length-4].isType=!0,n.tokens[n.\##
tokens.length-3].isType=!0,n.tokens[n.tokens.length-2].isType=!0,n.tokens[n.tokens.length-1].isType=!0}function Ur()\##
{if(g(c._abstract)&&O()===t._class)return n.type=t._abstract,h(),we(!0,!0),!0;if(g(c._interface)){let e=A(2);return \##
Yt(c._interface,!0),E(e),!0}return!1}function Wr(){if(n.type===t._const){let e=ge();if(e.type===t.name&&e.contextual\##
Keyword===c._enum)return f(t._const),q(c._enum),n.tokens[n.tokens.length-1].type=t._enum,a1(),!0}return!1}function V\##
r(e){let s=n.tokens.length;Tt([c._abstract,c._readonly,c._declare,c._static,c._override]);let r=n.tokens.length;if(v\##
r()){let a=e?s-1:s;for(let u=a;u<r;u++)n.tokens[u].isType=!0;return!0}return!1}function Gr(e){if(!sc(e))F()}function\##
 Xr(){let e=V(c._declare);if(e)n.tokens[n.tokens.length-1].type=t._declare;let s=!1;if(i(t.name))if(e){let r=A(2);s=\##
Cr(),E(r)}else s=Cr();if(!s)if(e){let r=A(2);te(!0),E(r)}else te(!0)}function Jr(e){if(e&&(i(t.lessThan)||i(t.bitShi\##
ftL)))l1();if(V(c._implements)){n.tokens[n.tokens.length-1].type=t._implements;let s=A(1);Or(),E(s)}}function zr(){P\##
e()}function Kr(){Pe()}function Yr(){let e=A(0);if(!K())p(t.bang);ve(),E(e)}function Qr(){if(i(t.colon))rt()}functio\##
n Zr(e,s){if(Ze)return rc(e,s);else return oc(e,s)}function rc(e,s){if(!i(t.lessThan))return ue(e,s);let r=n.snapsho\##
t(),o=ue(e,s);if(n.error)n.restoreFromSnapshot(r);else return o;if(n.type=t.typeParameterStart,zt(),o=ue(e,s),!o)w()\##
;return o}function oc(e,s){if(!i(t.lessThan))return ue(e,s);let r=n.snapshot();zt();let o=ue(e,s);if(!o)w();if(n.err\##
or)n.restoreFromSnapshot(r);else return o;return ue(e,s)}function eo(){if(i(t.colon)){let e=n.snapshot();if(wt(t.col\##
on),Q())w();if(!i(t.arrow))w();if(n.error)n.restoreFromSnapshot(e)}return p(t.arrow)}function Tr(){let e=A(0);p(t.qu\##
estion),ve(),E(e)}function to(){if(i(t.lessThan)||i(t.bitShiftL))l1();f1()}function ic(){let e=!1,s=!1;while(!0){if(\##
n.pos>=d.length){w("Unterminated JSX contents");return}let r=d.charCodeAt(n.pos);if(r===l.lessThan||r===l.leftCurlyB\##
race){if(n.pos===n.start){if(r===l.lessThan){n.pos++,S(t.jsxTagStart);return}Gn(r);return}if(e&&!s)S(t.jsxEmptyText)\##
;else S(t.jsxText);return}if(r===l.lineFeed)e=!0;else if(r!==l.space&&r!==l.carriageReturn&&r!==l.tab)s=!0;n.pos++}}\##
function ac(e){n.pos++;for(;;){if(n.pos>=d.length){w("Unterminated string constant");return}if(d.charCodeAt(n.pos)==\##
=e){n.pos++;break}n.pos++}S(t.string)}function cc(){let e;do{if(n.pos>d.length){w("Unexpectedly reached the end of i\##
nput.");return}e=d.charCodeAt(++n.pos)}while(ee[e]||e===l.dash);S(t.jsxName)}function h1(){ie()}function so(e){if(h1\##
(),!p(t.colon)){n.tokens[n.tokens.length-1].identifierRole=e;return}h1()}function no(){let e=n.tokens.length;so(_.Ac\##
cess);let s=!1;while(i(t.dot))s=!0,ie(),h1();if(!s){let r=n.tokens[e],o=d.charCodeAt(r.start);if(o>=l.lowercaseA&&o<\##
=l.lowercaseZ)r.identifierRole=null}}function lc(){switch(n.type){case t.braceL:h(),J(),ie();return;case t.jsxTagSta\##
rt:m1(),ie();return;case t.string:ie();return;default:w("JSX value should be either an expression or a quoted JSX te\##
xt")}}function uc(){f(t.ellipsis),J()}function pc(e){if(i(t.jsxTagEnd))return!1;if(no(),R)Fr();let s=!1;while(!i(t.s\##
lash)&&!i(t.jsxTagEnd)&&!n.error){if(p(t.braceL)){s=!0,f(t.ellipsis),X(),ie();continue}if(s&&n.end-n.start===3&&d.ch\##
arCodeAt(n.start)===l.lowercaseK&&d.charCodeAt(n.start+1)===l.lowercaseE&&d.charCodeAt(n.start+2)===l.lowercaseY)n.t\##
okens[e].jsxRole=oe.KeyAfterPropSpread;if(so(_.ObjectKey),i(t.eq))ie(),lc()}let r=i(t.slash);if(r)ie();return r}func\##
tion fc(){if(i(t.jsxTagEnd))return;no()}function ro(){let e=n.tokens.length-1;n.tokens[e].jsxRole=oe.NoChildren;let \##
s=0;if(!pc(e)){ct();while(!0)switch(n.type){case t.jsxTagStart:if(ie(),i(t.slash)){if(ie(),fc(),n.tokens[e].jsxRole!\##
==oe.KeyAfterPropSpread){if(s===1)n.tokens[e].jsxRole=oe.OneChild;else if(s>1)n.tokens[e].jsxRole=oe.StaticChildren}\##
return}s++,ro(),ct();break;case t.jsxText:s++,ct();break;case t.jsxEmptyText:ct();break;case t.braceL:if(h(),i(t.ell\##
ipsis))uc(),ct(),s+=2;else{if(!i(t.braceR))s++,J();ct()}break;default:w();return}}}function m1(){ie(),ro()}function \##
ie(){n.tokens.push(new tt),Vn(),n.start=n.pos;let e=d.charCodeAt(n.pos);if(_e[e])cc();else if(e===l.quotationMark||e\##
===l.apostrophe)ac(e);else switch(++n.pos,e){case l.greaterThan:S(t.jsxTagEnd);break;case l.lessThan:S(t.jsxTagStart\##
);break;case l.slash:S(t.slash);break;case l.equalsTo:S(t.eq);break;case l.leftCurlyBrace:S(t.braceL);break;case l.d\##
ot:S(t.dot);break;case l.colon:S(t.colon);break;default:w()}}function ct(){n.tokens.push(new tt),n.start=n.pos,ic()}\##
function oo(e){if(i(t.question)){let s=O();if(s===t.colon||s===t.comma||s===t.parenR)return}d1(e)}function io(){if($\##
t(t.question),i(t.colon)){if(R)rt();else if(v)Se()}}class ao{constructor(e){this.stop=e}}function J(e=!1){if(X(e),i(\##
t.comma))while(p(t.comma))X(e)}function X(e=!1,s=!1){if(R)return Zr(e,s);else if(v)return xo(e,s);else return ue(e,s\##
)}function ue(e,s){if(i(t._yield))return Cc(),!1;if(i(t.parenL)||i(t.name)||i(t._yield))n.potentialArrowAt=n.start;l\##
et r=hc(e);if(s)I1();if(n.type&t.IS_ASSIGN)return h(),X(e),!1;return r}function hc(e){if(dc(e))return!0;return mc(e)\##
,!1}function mc(e){if(R||v)oo(e);else d1(e)}function d1(e){if(p(t.question))X(),f(t.colon),X(e)}function dc(e){let s\##
=n.tokens.length;if(it())return!0;return Zt(s,-1,e),!1}function Zt(e,s,r){if(R&&(t._in&t.PRECEDENCE_MASK)>s&&!K()&&(\##
V(c._as)||V(c._satisfies))){let a=A(1);H(),E(a),Ht(),Zt(e,s,r);return}let o=n.type&t.PRECEDENCE_MASK;if(o>0&&(!r||!i\##
(t._in))){if(o>s){let a=n.type;if(h(),a===t.nullishCoalescing)n.tokens[n.tokens.length-1].nullishStartIndex=e;let u=\##
n.tokens.length;if(it(),Zt(u,a&t.IS_RIGHT_ASSOCIATIVE?o-1:o,r),a===t.nullishCoalescing)n.tokens[e].numNullishCoalesc\##
eStarts++,n.tokens[n.tokens.length-1].numNullishCoalesceEnds++;Zt(e,s,r)}}}function it(){if(R&&!Ze&&p(t.lessThan))re\##
turn Dr(),!1;if(g(c._module)&&Hn()===l.leftCurlyBrace&&!Bt())return Nc(),!1;if(n.type&t.IS_PREFIX)return h(),it(),!1\##
;if(k1())return!0;while(n.type&t.IS_POSTFIX&&!Q()){if(n.type===t.preIncDec)n.type=t.postIncDec;h()}return!1}function\##
 k1(){let e=n.tokens.length;if(pe())return!0;if(x1(e),n.tokens.length>e&&n.tokens[e].isOptionalChainStart)n.tokens[n\##
.tokens.length-1].isOptionalChainEnd=!0;return!1}function x1(e,s=!1){if(v)_o(e,s);else g1(e,s)}function g1(e,s=!1){l\##
et r=new ao(!1);do kc(e,s,r);while(!r.stop&&!n.error)}function kc(e,s,r){if(R)jr(e,s,r);else if(v)fo(e,s,r);else Et(\##
e,s,r)}function Et(e,s,r){if(!s&&p(t.doubleColon))_1(),r.stop=!0,x1(e,s);else if(i(t.questionDot)){if(n.tokens[e].is\##
OptionalChainStart=!0,s&&O()===t.parenL){r.stop=!0;return}if(h(),n.tokens[n.tokens.length-1].subscriptStartIndex=e,p\##
(t.bracketL))J(),f(t.bracketR);else if(p(t.parenL))me();else es()}else if(p(t.dot))n.tokens[n.tokens.length-1].subsc\##
riptStartIndex=e,es();else if(p(t.bracketL))n.tokens[n.tokens.length-1].subscriptStartIndex=e,J(),f(t.bracketR);else\##
 if(!s&&i(t.parenL))if(p1()){let o=n.snapshot(),a=n.tokens.length;h(),n.tokens[n.tokens.length-1].subscriptStartInde\##
x=e;let u=Re();if(n.tokens[n.tokens.length-1].contextId=u,me(),n.tokens[n.tokens.length-1].contextId=u,xc())n.restor\##
eFromSnapshot(o),r.stop=!0,n.scopeDepth++,be(),gc(a)}else{h(),n.tokens[n.tokens.length-1].subscriptStartIndex=e;let \##
o=Re();n.tokens[n.tokens.length-1].contextId=o,me(),n.tokens[n.tokens.length-1].contextId=o}else if(i(t.backQuote))Q\##
t();else r.stop=!0}function p1(){return n.tokens[n.tokens.length-1].contextualKeyword===c._async&&!Q()}function me()\##
{let e=!0;while(!p(t.parenR)&&!n.error){if(e)e=!1;else if(f(t.comma),p(t.parenR))break;uo(!1)}}function xc(){return \##
i(t.colon)||i(t.arrow)}function gc(e){if(R)Qr();else if(v)ko();f(t.arrow),lt(e)}function _1(){let e=n.tokens.length;\##
pe(),x1(e,!0)}function pe(){if(p(t.modulo))return b(),!1;if(i(t.jsxText)||i(t.jsxEmptyText))return Ne(),!1;else if(i\##
(t.lessThan)&&Ze)return n.type=t.jsxTagStart,m1(),h(),!1;let e=n.potentialArrowAt===n.start;switch(n.type){case t.sl\##
ash:case t.assign:Q1();case t._super:case t._this:case t.regexp:case t.num:case t.bigint:case t.decimal:case t.strin\##
g:case t._null:case t._true:case t._false:return h(),!1;case t._import:if(h(),i(t.dot))n.tokens[n.tokens.length-1].t\##
ype=t.name,h(),b();return!1;case t.name:{let s=n.tokens.length,r=n.start,o=n.contextualKeyword;if(b(),o===c._await)r\##
eturn Ac(),!1;else if(o===c._async&&i(t._function)&&!Q())return h(),Te(r,!1),!1;else if(e&&o===c._async&&!Q()&&i(t.n\##
ame))return n.scopeDepth++,he(!1),f(t.arrow),lt(s),!0;else if(i(t._do)&&!Q())return h(),Ee(),!1;if(e&&!Q()&&i(t.arro\##
w))return n.scopeDepth++,Xt(!1),f(t.arrow),lt(s),!0;return n.tokens[n.tokens.length-1].identifierRole=_.Access,!1}ca\##
se t._do:return h(),Ee(),!1;case t.parenL:return co(e);case t.bracketL:return h(),lo(t.bracketR,!0),!1;case t.braceL\##
:return bt(!1,!1),!1;case t._function:return _c(),!1;case t.at:rs();case t._class:return we(!1),!1;case t._new:retur\##
n yc(),!1;case t.backQuote:return Qt(),!1;case t.doubleColon:return h(),_1(),!1;case t.hash:{let s=Hn();if(_e[s]||s=\##
==l.backslash)es();else h();return!1}default:return w(),!1}}function es(){p(t.hash),b()}function _c(){let e=n.start;\##
if(b(),p(t.dot))b();Te(e,!1)}function Ne(){h()}function Ct(){f(t.parenL),J(),f(t.parenR)}function co(e){let s=n.snap\##
shot(),r=n.tokens.length;f(t.parenL);let o=!0;while(!i(t.parenR)&&!n.error){if(o)o=!1;else if(f(t.comma),i(t.parenR)\##
)break;if(i(t.ellipsis)){t1(!1),I1();break}else X(!1,!0)}if(f(t.parenR),e&&Ic()){if(ts()){if(n.restoreFromSnapshot(s\##
),n.scopeDepth++,be(),ts(),lt(r),n.error)return n.restoreFromSnapshot(s),co(!1),!1;return!0}}return!1}function Ic(){\##
return i(t.colon)||!Q()}function ts(){if(R)return eo();else if(v)return go();else return p(t.arrow)}function I1(){if\##
(R||v)io()}function yc(){if(f(t._new),p(t.dot)){b();return}if(Tc(),v)ho();if(p(t.parenL))lo(t.parenR)}function Tc(){\##
_1(),p(t.questionDot)}function Qt(){de(),de();while(!i(t.backQuote)&&!n.error)f(t.dollarBraceL),J(),de(),de();h()}fu\##
nction bt(e,s){let r=Re(),o=!0;h(),n.tokens[n.tokens.length-1].contextId=r;while(!p(t.braceR)&&!n.error){if(o)o=!1;e\##
lse if(f(t.comma),p(t.braceR))break;let a=!1;if(i(t.ellipsis)){let u=n.tokens.length;if(e1(),e){if(n.tokens.length==\##
=u+2)Xt(s);if(p(t.braceR))break}continue}if(!e)a=p(t.star);if(!e&&g(c._async)){if(a)w();if(b(),i(t.colon)||i(t.paren\##
L)||i(t.braceR)||i(t.eq)||i(t.comma));else{if(i(t.star))h(),a=!0;Le(r)}}else Le(r);Ec(e,s,r)}n.tokens[n.tokens.lengt\##
h-1].contextId=r}function bc(e){return!e&&(i(t.string)||i(t.num)||i(t.bracketL)||i(t.name)||!!(n.type&t.IS_KEYWORD))\##
}function wc(e,s){let r=n.start;if(i(t.parenL)){if(e)w();return ss(r,!1),!0}if(bc(e))return Le(s),ss(r,!1),!0;return\##
!1}function Sc(e,s){if(p(t.colon)){if(e)_t(s);else X(!1);return}let r;if(e)if(n.scopeDepth===0)r=_.ObjectShorthandTo\##
pLevelDeclaration;else if(s)r=_.ObjectShorthandBlockScopedDeclaration;else r=_.ObjectShorthandFunctionScopedDeclarat\##
ion;else r=_.ObjectShorthand;n.tokens[n.tokens.length-1].identifierRole=r,_t(s,!0)}function Ec(e,s,r){if(R)zr();else\##
 if(v)mo();if(!wc(e,r))Sc(e,s)}function Le(e){if(v)ns();if(p(t.bracketL))n.tokens[n.tokens.length-1].contextId=e,X()\##
,f(t.bracketR),n.tokens[n.tokens.length-1].contextId=e;else{if(i(t.num)||i(t.string)||i(t.bigint)||i(t.decimal))pe()\##
;else es();n.tokens[n.tokens.length-1].identifierRole=_.ObjectKey,n.tokens[n.tokens.length-1].contextId=e}}function \##
ss(e,s){let r=Re();n.scopeDepth++;let o=n.tokens.length;be(s,r),y1(e,r);let u=n.tokens.length;n.scopes.push(new re(o\##
,u,!0)),n.scopeDepth--}function lt(e){De(!0);let s=n.tokens.length;n.scopes.push(new re(e,s,!0)),n.scopeDepth--}func\##
tion y1(e,s=0){if(R)Br(e,s);else if(v)po(s);else De(!1,s)}function De(e,s=0){if(e&&!i(t.braceL))X();else Ee(!0,s)}fu\##
nction lo(e,s=!1){let r=!0;while(!p(e)&&!n.error){if(r)r=!1;else if(f(t.comma),p(e))break;uo(s)}}function uo(e){if(e\##
&&i(t.comma));else if(i(t.ellipsis))e1(),I1();else if(i(t.question))h();else X(!1,!0)}function b(){h(),n.tokens[n.to\##
kens.length-1].type=t.name}function Ac(){it()}function Cc(){if(h(),!i(t.semi)&&!Q())p(t.star),X()}function Nc(){q(c.\##
_module),f(t.braceL),at(t.braceR)}function Pc(e){return(e.type===t.name||!!(e.type&t.IS_KEYWORD))&&e.contextualKeywo\##
rd!==c._from}function xe(e){let s=A(0);f(e||t.colon),ne(),E(s)}function Io(){if(f(t.modulo),q(c._checks),p(t.parenL)\##
)J(),f(t.parenR)}function w1(){let e=A(0);if(f(t.colon),i(t.modulo))Io();else if(ne(),i(t.modulo))Io();E(e)}function\##
 Rc(){h(),S1(!0)}function vc(){if(h(),b(),i(t.lessThan))fe();f(t.parenL),b1(),f(t.parenR),w1(),F()}function T1(){if(\##
i(t._class))Rc();else if(i(t._function))vc();else if(i(t._var))Lc();else if(V(c._module))if(p(t.dot))Oc();else Dc();\##
else if(g(c._type))Mc();else if(g(c._opaque))Bc();else if(g(c._interface))jc();else if(i(t._export))Fc();else w()}fu\##
nction Lc(){h(),Eo(),F()}function Dc(){if(i(t.string))pe();else b();f(t.braceL);while(!i(t.braceR)&&!n.error)if(i(t.\##
_import))h(),v1();else w();f(t.braceR)}function Fc(){if(f(t._export),p(t._default))if(i(t._function)||i(t._class))T1\##
();else ne(),F();else if(i(t._var)||i(t._function)||i(t._class)||g(c._opaque))T1();else if(i(t.star)||i(t.braceL)||g\##
(c._interface)||g(c._type)||g(c._opaque))R1();else w()}function Oc(){q(c._exports),Se(),F()}function Mc(){h(),A1()}f\##
unction Bc(){h(),C1(!0)}function jc(){h(),S1()}function S1(e=!1){if(ls(),i(t.lessThan))fe();if(p(t._extends))do os()\##
;while(!e&&p(t.comma));if(g(c._mixins)){h();do os();while(p(t.comma))}if(g(c._implements)){h();do os();while(p(t.com\##
ma))}is(e,!1,e)}function os(){if(bo(!1),i(t.lessThan))Fe()}function E1(){S1()}function ls(){b()}function A1(){if(ls(\##
),i(t.lessThan))fe();xe(t.eq),F()}function C1(e){if(q(c._type),ls(),i(t.lessThan))fe();if(i(t.colon))xe(t.colon);if(\##
!e)xe(t.eq);F()}function qc(){if(ns(),Eo(),p(t.eq))ne()}function fe(){let e=A(0);if(i(t.lessThan)||i(t.typeParameter\##
Start))h();else w();do if(qc(),!i(t.greaterThan))f(t.comma);while(!i(t.greaterThan)&&!n.error);f(t.greaterThan),E(e)\##
}function Fe(){let e=A(0);f(t.lessThan);while(!i(t.greaterThan)&&!n.error)if(ne(),!i(t.greaterThan))f(t.comma);f(t.g\##
reaterThan),E(e)}function $c(){if(q(c._interface),p(t._extends))do os();while(p(t.comma));is(!1,!1,!1)}function N1()\##
{if(i(t.num)||i(t.string))pe();else b()}function Hc(){if(O()===t.colon)N1(),xe();else ne();f(t.bracketR),xe()}functi\##
on Uc(){if(N1(),f(t.bracketR),f(t.bracketR),i(t.lessThan)||i(t.parenL))P1();else p(t.question),xe()}function P1(){if\##
(i(t.lessThan))fe();f(t.parenL);while(!i(t.parenR)&&!i(t.ellipsis)&&!n.error)if(as(),!i(t.parenR))f(t.comma);if(p(t.\##
ellipsis))as();f(t.parenR),xe()}function Wc(){P1()}function is(e,s,r){let o;if(s&&i(t.braceBarL))f(t.braceBarL),o=t.\##
braceBarR;else f(t.braceL),o=t.braceR;while(!i(o)&&!n.error){if(r&&g(c._proto)){let a=O();if(a!==t.colon&&a!==t.ques\##
tion)h(),e=!1}if(e&&g(c._static)){let a=O();if(a!==t.colon&&a!==t.question)h()}if(ns(),p(t.bracketL))if(p(t.bracketL\##
))Uc();else Hc();else if(i(t.parenL)||i(t.lessThan))Wc();else{if(g(c._get)||g(c._set)){let a=O();if(a===t.name||a===\##
t.string||a===t.num)h()}Vc()}Gc()}f(o)}function Vc(){if(i(t.ellipsis)){if(f(t.ellipsis),!p(t.comma))p(t.semi);if(i(t\##
.braceR))return;ne()}else if(N1(),i(t.lessThan)||i(t.parenL))P1();else p(t.question),xe()}function Gc(){if(!p(t.semi\##
)&&!p(t.comma)&&!i(t.braceR)&&!i(t.braceBarR))w()}function bo(e){if(!e)b();while(p(t.dot))b()}function Xc(){if(bo(!0\##
),i(t.lessThan))Fe()}function Jc(){f(t._typeof),wo()}function zc(){f(t.bracketL);while(n.pos<d.length&&!i(t.bracketR\##
)){if(ne(),i(t.bracketR))break;f(t.comma)}f(t.bracketR)}function as(){let e=O();if(e===t.colon||e===t.question)b(),p\##
(t.question),xe();else ne()}function b1(){while(!i(t.parenR)&&!i(t.ellipsis)&&!n.error)if(as(),!i(t.parenR))f(t.comm\##
a);if(p(t.ellipsis))as()}function wo(){let e=!1,s=n.noAnonFunctionType;switch(n.type){case t.name:{if(g(c._interface\##
)){$c();return}b(),Xc();return}case t.braceL:is(!1,!1,!1);return;case t.braceBarL:is(!1,!0,!1);return;case t.bracket\##
L:zc();return;case t.lessThan:fe(),f(t.parenL),b1(),f(t.parenR),f(t.arrow),ne();return;case t.parenL:if(h(),!i(t.par\##
enR)&&!i(t.ellipsis))if(i(t.name)){let r=O();e=r!==t.question&&r!==t.colon}else e=!0;if(e)if(n.noAnonFunctionType=!1\##
,ne(),n.noAnonFunctionType=s,n.noAnonFunctionType||!(i(t.comma)||i(t.parenR)&&O()===t.arrow)){f(t.parenR);return}els\##
e p(t.comma);b1(),f(t.parenR),f(t.arrow),ne();return;case t.minus:h(),Ne();return;case t.string:case t.num:case t._t\##
rue:case t._false:case t._null:case t._this:case t._void:case t.star:h();return;default:if(n.type===t._typeof){Jc();\##
return}else if(n.type&t.IS_KEYWORD){h(),n.tokens[n.tokens.length-1].type=t.name;return}}w()}function Kc(){wo();while\##
(!Q()&&(i(t.bracketL)||i(t.questionDot)))if(p(t.questionDot),f(t.bracketL),p(t.bracketR));else ne(),f(t.bracketR)}fu\##
nction So(){if(p(t.question))So();else Kc()}function yo(){if(So(),!n.noAnonFunctionType&&p(t.arrow))ne()}function To\##
(){p(t.bitwiseAND),yo();while(p(t.bitwiseAND))yo()}function Yc(){p(t.bitwiseOR),To();while(p(t.bitwiseOR))To()}funct\##
ion ne(){Yc()}function Se(){xe()}function Eo(){if(b(),i(t.colon))Se()}function ns(){if(i(t.plus)||i(t.minus))h(),n.t\##
okens[n.tokens.length-1].isType=!0}function po(e){if(i(t.colon))w1();De(!1,e)}function fo(e,s,r){if(i(t.questionDot)\##
&&O()===t.lessThan){if(s){r.stop=!0;return}h(),Fe(),f(t.parenL),me();return}else if(!s&&i(t.lessThan)){let o=n.snaps\##
hot();if(Fe(),f(t.parenL),me(),n.error)n.restoreFromSnapshot(o);else return}Et(e,s,r)}function ho(){if(i(t.lessThan)\##
){let e=n.snapshot();if(Fe(),n.error)n.restoreFromSnapshot(e)}}function Ao(){if(i(t.name)&&n.contextualKeyword===c._\##
interface){let e=A(0);return h(),E1(),E(e),!0}else if(g(c._enum))return qo(),!0;return!1}function Co(){if(g(c._enum)\##
)return qo(),!0;return!1}function No(e){if(e===c._declare){if(i(t._class)||i(t.name)||i(t._function)||i(t._var)||i(t\##
._export)){let s=A(1);T1(),E(s)}}else if(i(t.name)){if(e===c._interface){let s=A(1);E1(),E(s)}else if(e===c._type){l\##
et s=A(1);A1(),E(s)}else if(e===c._opaque){let s=A(1);C1(!1),E(s)}}F()}function Po(){return g(c._type)||g(c._interfa\##
ce)||g(c._opaque)||g(c._enum)}function Ro(){return i(t.name)&&(n.contextualKeyword===c._type||n.contextualKeyword===\##
c._interface||n.contextualKeyword===c._opaque||n.contextualKeyword===c._enum)}function vo(){if(g(c._type)){let e=A(1\##
);if(h(),i(t.braceL))us(),ut();else A1();E(e)}else if(g(c._opaque)){let e=A(1);h(),C1(!1),E(e)}else if(g(c._interfac\##
e)){let e=A(1);h(),E1(),E(e)}else te(!0)}function Lo(){return i(t.star)||g(c._type)&&O()===t.star}function Do(){if(V\##
(c._type)){let e=A(2);cs(),E(e)}else cs()}function Fo(e){if(e&&i(t.lessThan))Fe();if(g(c._implements)){let s=A(0);h(\##
),n.tokens[n.tokens.length-1].type=t._implements;do if(ls(),i(t.lessThan))Fe();while(p(t.comma));E(s)}}function mo()\##
{if(i(t.lessThan)){if(fe(),!i(t.parenL))w()}}function br(){let e=A(0);if(p(t.question),i(t.colon))Se();E(e)}function\##
 Oo(){if(i(t._typeof)||g(c._type)){let e=ge();if(Pc(e)||e.type===t.braceL||e.type===t.star)h()}}function Mo(){let e=\##
n.contextualKeyword===c._type||n.type===t._typeof;if(e)h();else b();if(g(c._as)&&!et(c._as))if(b(),e&&!i(t.name)&&!(\##
n.type&t.IS_KEYWORD));else b();else{if(e&&(i(t.name)||!!(n.type&t.IS_KEYWORD)))b();if(V(c._as))b()}}function Bo(){if\##
(i(t.lessThan)){let e=A(0);fe(),E(e)}}function jo(){if(i(t.colon))Se()}function ko(){if(i(t.colon)){let e=n.noAnonFu\##
nctionType;n.noAnonFunctionType=!0,Se(),n.noAnonFunctionType=e}}function xo(e,s){if(i(t.lessThan)){let r=n.snapshot(\##
),o=ue(e,s);if(n.error)n.restoreFromSnapshot(r),n.type=t.typeParameterStart;else return o;let a=A(0);if(fe(),E(a),o=\##
ue(e,s),o)return!0;w()}return ue(e,s)}function go(){if(i(t.colon)){let e=A(0),s=n.snapshot(),r=n.noAnonFunctionType;\##
if(n.noAnonFunctionType=!0,w1(),n.noAnonFunctionType=r,Q())w();if(!i(t.arrow))w();if(n.error)n.restoreFromSnapshot(s\##
);E(e)}return p(t.arrow)}function _o(e,s=!1){if(n.tokens[n.tokens.length-1].contextualKeyword===c._async&&i(t.lessTh\##
an)){let r=n.snapshot();if(Qc()&&!n.error)return;n.restoreFromSnapshot(r)}g1(e,s)}function Qc(){n.scopeDepth++;let e\##
=n.tokens.length;if(be(),!ts())return!1;return lt(e),!0}function qo(){q(c._enum),n.tokens[n.tokens.length-1].type=t.\##
_enum,b(),Zc()}function Zc(){if(V(c._of))h();f(t.braceL),el(),f(t.braceR)}function el(){while(!i(t.braceR)&&!n.error\##
){if(p(t.ellipsis))break;if(tl(),!i(t.braceR))f(t.comma)}}function tl(){if(b(),p(t.eq))h()}function Wo(){if(at(t.eof\##
),n.scopes.push(new re(0,n.tokens.length,!0)),n.scopeDepth!==0)throw Error(`Invalid scope depth at end of file: ${n.\##
scopeDepth}`);return new D1(n.tokens,n.scopes)}function te(e){if(v){if(Ao())return}if(i(t.at))rs();sl(e)}function sl\##
(e){if(R){if(Wr())return}let s=n.type;switch(s){case t._break:case t._continue:rl();return;case t._debugger:ol();ret\##
urn;case t._do:il();return;case t._for:al();return;case t._function:if(O()===t.dot)break;if(!e)w();ul();return;case \##
t._class:if(!e)w();we(!0);return;case t._if:pl();return;case t._return:fl();return;case t._switch:hl();return;case t\##
._throw:ml();return;case t._try:kl();return;case t._let:case t._const:if(!e)w();case t._var:At(s!==t._var);return;ca\##
se t._while:xl();return;case t.braceL:Ee();return;case t.semi:gl();return;case t._export:case t._import:{let a=O();i\##
f(a===t.parenL||a===t.dot)break;if(h(),s===t._import)v1();else R1();return}case t.name:if(n.contextualKeyword===c._a\##
sync){let a=n.start,u=n.snapshot();if(h(),i(t._function)&&!Q()){f(t._function),Te(a,!0);return}else n.restoreFromSna\##
pshot(u)}else if(n.contextualKeyword===c._using&&!Bt()&&O()===t.name){At(!0);return}else if(Vo()){q(c._await),At(!0)\##
;return}default:break}let r=n.tokens.length;J();let o=null;if(n.tokens.length===r+1){let a=n.tokens[n.tokens.length-\##
1];if(a.type===t.name)o=a.contextualKeyword}if(o==null){F();return}if(p(t.colon))_l();else Il(o)}function Vo(){if(!g\##
(c._await))return!1;let e=n.snapshot();if(h(),!g(c._using)||K())return n.restoreFromSnapshot(e),!1;if(h(),!i(t.name)\##
||K())return n.restoreFromSnapshot(e),!1;return n.restoreFromSnapshot(e),!0}function rs(){while(i(t.at))Go()}functio\##
n Go(){if(h(),p(t.parenL))J(),f(t.parenR);else{b();while(p(t.dot))b();nl()}}function nl(){if(R)to();else f1()}functi\##
on f1(){if(p(t.parenL))me()}function rl(){if(h(),!le())b(),F()}function ol(){h(),F()}function il(){h(),te(!1),f(t._w\##
hile),Ct(),p(t.semi)}function al(){n.scopeDepth++;let e=n.tokens.length;ll();let s=n.tokens.length;n.scopes.push(new\##
 re(e,s,!1)),n.scopeDepth--}function cl(){if(!g(c._using))return!1;if(et(c._of))return!1;return!0}function ll(){h();\##
let e=!1;if(g(c._await))e=!0,h();if(f(t.parenL),i(t.semi)){if(e)w();L1();return}let s=Vo();if(s||i(t._var)||i(t._let\##
)||i(t._const)||cl()){if(s)q(c._await);if(h(),Xo(!0,n.type!==t._var),i(t._in)||g(c._of)){$o(e);return}L1();return}if\##
(J(!0),i(t._in)||g(c._of)){$o(e);return}if(e)w();L1()}function ul(){let e=n.start;h(),Te(e,!0)}function pl(){if(h(),\##
Ct(),te(!1),p(t._else))te(!1)}function fl(){if(h(),!le())J(),F()}function hl(){h(),Ct(),n.scopeDepth++;let e=n.token\##
s.length;f(t.braceL);while(!i(t.braceR)&&!n.error)if(i(t._case)||i(t._default)){let r=i(t._case);if(h(),r)J();f(t.co\##
lon)}else te(!0);h();let s=n.tokens.length;n.scopes.push(new re(e,s,!1)),n.scopeDepth--}function ml(){h(),J(),F()}fu\##
nction dl(){if(It(!0),R)ve()}function kl(){if(h(),Ee(),i(t._catch)){h();let e=null;if(i(t.parenL))n.scopeDepth++,e=n\##
.tokens.length,f(t.parenL),dl(),f(t.parenR);if(Ee(),e!=null){let s=n.tokens.length;n.scopes.push(new re(e,s,!1)),n.s\##
copeDepth--}}if(p(t._finally))Ee()}function At(e){h(),Xo(!1,e),F()}function xl(){h(),Ct(),te(!1)}function gl(){h()}f\##
unction _l(){te(!0)}function Il(e){if(R)Gr(e);else if(v)No(e);else F()}function Ee(e=!1,s=0){let r=n.tokens.length;i\##
f(n.scopeDepth++,f(t.braceL),s)n.tokens[n.tokens.length-1].contextId=s;if(at(t.braceR),s)n.tokens[n.tokens.length-1]\##
.contextId=s;let o=n.tokens.length;n.scopes.push(new re(r,o,e)),n.scopeDepth--}function at(e){while(!p(e)&&!n.error)\##
te(!0)}function L1(){if(f(t.semi),!i(t.semi))J();if(f(t.semi),!i(t.parenR))J();f(t.parenR),te(!1)}function $o(e){if(\##
e)V(c._of);else h();J(),f(t.parenR),te(!1)}function Xo(e,s){while(!0){if(yl(s),p(t.eq)){let r=n.tokens.length-1;X(e)\##
,n.tokens[r].rhsEndIndex=n.tokens.length}if(!p(t.comma))break}}function yl(e){if(It(e),R)Yr();else if(v)jo()}functio\##
n Te(e,s,r=!1){if(i(t.star))h();if(s&&!r&&!i(t.name)&&!i(t._yield))w();let o=null;if(i(t.name)){if(!s)o=n.tokens.len\##
gth,n.scopeDepth++;he(!1)}let a=n.tokens.length;n.scopeDepth++,be(),y1(e);let u=n.tokens.length;if(n.scopes.push(new\##
 re(a,u,!0)),n.scopeDepth--,o!==null)n.scopes.push(new re(o,u,!0)),n.scopeDepth--}function be(e=!1,s=0){if(R)Kr();el\##
se if(v)Bo();if(f(t.parenL),s)n.tokens[n.tokens.length-1].contextId=s;if(yt(t.parenR,!1,!1,e,s),s)n.tokens[n.tokens.\##
length-1].contextId=s}function we(e,s=!1){let r=Re();h(),n.tokens[n.tokens.length-1].contextId=r,n.tokens[n.tokens.l\##
ength-1].isExpression=!e;let o=null;if(!e)o=n.tokens.length,n.scopeDepth++;Sl(e,s),El();let a=n.tokens.length;if(Tl(\##
r),n.error)return;if(n.tokens[a].contextId=r,n.tokens[n.tokens.length-1].contextId=r,o!==null){let u=n.tokens.length\##
;n.scopes.push(new re(o,u,!1)),n.scopeDepth--}}function Jo(){return i(t.eq)||i(t.semi)||i(t.braceR)||i(t.bang)||i(t.\##
colon)}function zo(){return i(t.parenL)||i(t.lessThan)}function Tl(e){f(t.braceL);while(!p(t.braceR)&&!n.error){if(p\##
(t.semi))continue;if(i(t.at)){Go();continue}let s=n.start;bl(s,e)}}function bl(e,s){if(R)Tt([c._declare,c._public,c.\##
_protected,c._private,c._override]);let r=!1;if(i(t.name)&&n.contextualKeyword===c._static){if(b(),zo()){Pt(e,!1);re\##
turn}else if(Jo()){ps();return}if(n.tokens[n.tokens.length-1].type=t._static,r=!0,i(t.braceL)){n.tokens[n.tokens.len\##
gth-1].contextId=s,Ee();return}}wl(e,r,s)}function wl(e,s,r){if(R){if(Vr(s))return}if(p(t.star)){Nt(r),Pt(e,!1);retu\##
rn}Nt(r);let o=!1,a=n.tokens[n.tokens.length-1];if(a.contextualKeyword===c._constructor)o=!0;if(Ho(),zo())Pt(e,o);el\##
se if(Jo())ps();else if(a.contextualKeyword===c._async&&!le()){if(n.tokens[n.tokens.length-1].type=t._async,i(t.star\##
))h();Nt(r),Ho(),Pt(e,!1)}else if((a.contextualKeyword===c._get||a.contextualKeyword===c._set)&&!(le()&&i(t.star))){\##
if(a.contextualKeyword===c._get)n.tokens[n.tokens.length-1].type=t._get;else n.tokens[n.tokens.length-1].type=t._set\##
;Nt(r),Pt(e,!1)}else if(a.contextualKeyword===c._accessor&&!le())Nt(r),ps();else if(le())ps();else w()}function Pt(e\##
,s){if(R)Pe();else if(v){if(i(t.lessThan))fe()}ss(e,s)}function Nt(e){Le(e)}function Ho(){if(R){let e=A(0);p(t.quest\##
ion),E(e)}}function ps(){if(R)$t(t.bang),ve();else if(v){if(i(t.colon))Se()}if(i(t.eq)){let e=n.tokens.length;h(),X(\##
),n.tokens[e].rhsEndIndex=n.tokens.length}F()}function Sl(e,s=!1){if(R&&(!e||s)&&g(c._implements))return;if(i(t.name\##
))he(!0);if(R)Pe();else if(v){if(i(t.lessThan))fe()}}function El(){let e=!1;if(p(t._extends))k1(),e=!0;else e=!1;if(\##
R)Jr(e);else if(v)Fo(e)}function R1(){let e=n.tokens.length-1;if(R){if(qr())return}if(Pl())Rl();else if(Nl()){if(b()\##
,i(t.comma)&&O()===t.star)f(t.comma),f(t.star),q(c._as),b();else Ko();ut()}else if(p(t._default))Al();else if(Ll())C\##
l();else us(),ut();n.tokens[e].rhsEndIndex=n.tokens.length}function Al(){if(R){if(Ur())return}if(v){if(Co())return}l\##
et e=n.start;if(p(t._function))Te(e,!0,!0);else if(g(c._async)&&O()===t._function)V(c._async),p(t._function),Te(e,!0\##
,!0);else if(i(t._class))we(!0,!0);else if(i(t.at))rs(),we(!0,!0);else X(),F()}function Cl(){if(R)Xr();else if(v)vo(\##
);else te(!0)}function Nl(){if(R&&u1())return!1;else if(v&&Ro())return!1;if(i(t.name))return n.contextualKeyword!==c\##
._async;if(!i(t._default))return!1;let e=ht(),s=ge(),r=s.type===t.name&&s.contextualKeyword===c._from;if(s.type===t.\##
comma)return!0;if(r){let o=d.charCodeAt($n(e+4));return o===l.quotationMark||o===l.apostrophe}return!1}function Ko()\##
{if(p(t.comma))us()}function ut(){if(V(c._from))pe(),Yo();F()}function Pl(){if(v)return Lo();else return i(t.star)}f\##
unction Rl(){if(v)Do();else cs()}function cs(){if(f(t.star),g(c._as))vl();else ut()}function vl(){h(),n.tokens[n.tok\##
ens.length-1].type=t._as,b(),Ko(),ut()}function Ll(){return R&&u1()||v&&Po()||n.type===t._var||n.type===t._const||n.\##
type===t._let||n.type===t._function||n.type===t._class||g(c._async)||i(t.at)}function us(){let e=!0;f(t.braceL);whil\##
e(!p(t.braceR)&&!n.error){if(e)e=!1;else if(f(t.comma),p(t.braceR))break;Dl()}}function Dl(){if(R){Hr();return}if(b(\##
),n.tokens[n.tokens.length-1].identifierRole=_.ExportAccess,V(c._as))b()}function Fl(){let e=n.snapshot();if(q(c._mo\##
dule),V(c._from))if(g(c._from))return n.restoreFromSnapshot(e),!0;else return n.restoreFromSnapshot(e),!1;else if(i(\##
t.comma))return n.restoreFromSnapshot(e),!1;else return n.restoreFromSnapshot(e),!0}function Ol(){if(g(c._module)&&F\##
l())h()}function v1(){if(R&&i(t.name)&&O()===t.eq){Kt();return}if(R&&g(c._type)){let e=ge();if(e.type===t.name&&e.co\##
ntextualKeyword!==c._from){if(q(c._type),O()===t.eq){Kt();return}}else if(e.type===t.star||e.type===t.braceL)q(c._ty\##
pe)}if(i(t.string))pe();else Ol(),Bl(),q(c._from),pe();Yo(),F()}function Ml(){return i(t.name)}function Uo(){st()}fu\##
nction Bl(){if(v)Oo();let e=!0;if(Ml()){if(Uo(),!p(t.comma))return}if(i(t.star)){h(),q(c._as),Uo();return}f(t.braceL\##
);while(!p(t.braceR)&&!n.error){if(e)e=!1;else{if(p(t.colon))w("ES2015 named imports do not destructure. Use another\##
 statement for destructuring after the import.");if(f(t.comma),p(t.braceR))break}jl()}}function jl(){if(R){$r();retu\##
rn}if(v){Mo();return}if(st(),g(c._as))n.tokens[n.tokens.length-1].identifierRole=_.ImportAccess,h(),st()}function Yo\##
(){if(i(t._with)||g(c._assert)&&!K())h(),bt(!1,!1)}function Qo(){if(n.pos===0&&d.charCodeAt(0)===l.numberSign&&d.cha\##
rCodeAt(1)===l.exclamationMark)Wn(2);return Un(),Wo()}class D1{constructor(e,s){this.tokens=e,this.scopes=s}}functio\##
n Zo(e,s,r,o){if(o&&r)throw Error("Cannot combine flow and typescript plugins.");X1(e,s,r,o);let a=Qo();if(n.error)t\##
hrow V1(n.error);return a}function F1(e){let s=e.currentIndex(),r=0,o=e.currentToken();do{let a=e.tokens[s];if(a.isO\##
ptionalChainStart)r++;if(a.isOptionalChainEnd)r--;if(r+=a.numNullishCoalesceStarts,r-=a.numNullishCoalesceEnds,a.con\##
textualKeyword===c._await&&a.identifierRole==null&&a.scopeDepth===o.scopeDepth)return!0;s+=1}while(r>0&&s<e.tokens.l\##
ength);return!1}class Oe{__init(){this.resultCode=""}__init2(){this.resultMappings=Array(this.tokens.length)}__init3\##
(){this.tokenIndex=0}constructor(e,s,r,o,a){this.code=e,this.tokens=s,this.isFlowEnabled=r,this.disableESTransforms=\##
o,this.helperManager=a,Oe.prototype.__init.call(this),Oe.prototype.__init2.call(this),Oe.prototype.__init3.call(this\##
)}snapshot(){return{resultCode:this.resultCode,tokenIndex:this.tokenIndex}}restoreToSnapshot(e){this.resultCode=e.re\##
sultCode,this.tokenIndex=e.tokenIndex}dangerouslyGetAndRemoveCodeSinceSnapshot(e){let s=this.resultCode.slice(e.resu\##
ltCode.length);return this.resultCode=e.resultCode,s}reset(){this.resultCode="",this.resultMappings=Array(this.token\##
s.length),this.tokenIndex=0}matchesContextualAtIndex(e,s){return this.matches1AtIndex(e,t.name)&&this.tokens[e].cont\##
extualKeyword===s}identifierNameAtIndex(e){return this.identifierNameForToken(this.tokens[e])}identifierNameAtRelati\##
veIndex(e){return this.identifierNameForToken(this.tokenAtRelativeIndex(e))}identifierName(){return this.identifierN\##
ameForToken(this.currentToken())}identifierNameForToken(e){return this.code.slice(e.start,e.end)}rawCodeForToken(e){\##
return this.code.slice(e.start,e.end)}stringValueAtIndex(e){return this.stringValueForToken(this.tokens[e])}stringVa\##
lue(){return this.stringValueForToken(this.currentToken())}stringValueForToken(e){return this.code.slice(e.start+1,e\##
.end-1)}matches1AtIndex(e,s){return this.tokens[e].type===s}matches2AtIndex(e,s,r){return this.tokens[e].type===s&&t\##
his.tokens[e+1].type===r}matches3AtIndex(e,s,r,o){return this.tokens[e].type===s&&this.tokens[e+1].type===r&&this.to\##
kens[e+2].type===o}matches1(e){return this.tokens[this.tokenIndex].type===e}matches2(e,s){return this.tokens[this.to\##
kenIndex].type===e&&this.tokens[this.tokenIndex+1].type===s}matches3(e,s,r){return this.tokens[this.tokenIndex].type\##
===e&&this.tokens[this.tokenIndex+1].type===s&&this.tokens[this.tokenIndex+2].type===r}matches4(e,s,r,o){return this\##
.tokens[this.tokenIndex].type===e&&this.tokens[this.tokenIndex+1].type===s&&this.tokens[this.tokenIndex+2].type===r&\##
&this.tokens[this.tokenIndex+3].type===o}matches5(e,s,r,o,a){return this.tokens[this.tokenIndex].type===e&&this.toke\##
ns[this.tokenIndex+1].type===s&&this.tokens[this.tokenIndex+2].type===r&&this.tokens[this.tokenIndex+3].type===o&&th\##
is.tokens[this.tokenIndex+4].type===a}matchesContextual(e){return this.matchesContextualAtIndex(this.tokenIndex,e)}m\##
atchesContextIdAndLabel(e,s){return this.matches1(e)&&this.currentToken().contextId===s}previousWhitespaceAndComment\##
s(){let e=this.code.slice(this.tokenIndex>0?this.tokens[this.tokenIndex-1].end:0,this.tokenIndex<this.tokens.length?\##
this.tokens[this.tokenIndex].start:this.code.length);if(this.isFlowEnabled)e=e.replace(/@flow/g,"");return e}replace\##
Token(e){this.resultCode+=this.previousWhitespaceAndComments(),this.appendTokenPrefix(),this.resultMappings[this.tok\##
enIndex]=this.resultCode.length,this.resultCode+=e,this.appendTokenSuffix(),this.tokenIndex++}replaceTokenTrimmingLe\##
ftWhitespace(e){this.resultCode+=this.previousWhitespaceAndComments().replace(/[^\r\n]/g,""),this.appendTokenPrefix(\##
),this.resultMappings[this.tokenIndex]=this.resultCode.length,this.resultCode+=e,this.appendTokenSuffix(),this.token\##
Index++}removeInitialToken(){this.replaceToken("")}removeToken(){this.replaceTokenTrimmingLeftWhitespace("")}removeB\##
alancedCode(){let e=0;while(!this.isAtEnd()){if(this.matches1(t.braceL))e++;else if(this.matches1(t.braceR)){if(e===\##
0)return;e--}this.removeToken()}}copyExpectedToken(e){if(this.tokens[this.tokenIndex].type!==e)throw Error(`Expected\##
 token ${e}`);this.copyToken()}copyToken(){this.resultCode+=this.previousWhitespaceAndComments(),this.appendTokenPre\##
fix(),this.resultMappings[this.tokenIndex]=this.resultCode.length,this.resultCode+=this.code.slice(this.tokens[this.\##
tokenIndex].start,this.tokens[this.tokenIndex].end),this.appendTokenSuffix(),this.tokenIndex++}copyTokenWithPrefix(e\##
){this.resultCode+=this.previousWhitespaceAndComments(),this.appendTokenPrefix(),this.resultCode+=e,this.resultMappi\##
ngs[this.tokenIndex]=this.resultCode.length,this.resultCode+=this.code.slice(this.tokens[this.tokenIndex].start,this\##
.tokens[this.tokenIndex].end),this.appendTokenSuffix(),this.tokenIndex++}appendTokenPrefix(){let e=this.currentToken\##
();if(e.numNullishCoalesceStarts||e.isOptionalChainStart)e.isAsyncOperation=F1(this);if(this.disableESTransforms)ret\##
urn;if(e.numNullishCoalesceStarts)for(let s=0;s<e.numNullishCoalesceStarts;s++){if(e.isAsyncOperation)this.resultCod\##
e+="await ",this.resultCode+=this.helperManager.getHelperName("asyncNullishCoalesce");else this.resultCode+=this.hel\##
perManager.getHelperName("nullishCoalesce");this.resultCode+="("}if(e.isOptionalChainStart){if(e.isAsyncOperation)th\##
is.resultCode+="await ";if(this.tokenIndex>0&&this.tokenAtRelativeIndex(-1).type===t._delete)if(e.isAsyncOperation)t\##
his.resultCode+=this.helperManager.getHelperName("asyncOptionalChainDelete");else this.resultCode+=this.helperManage\##
r.getHelperName("optionalChainDelete");else if(e.isAsyncOperation)this.resultCode+=this.helperManager.getHelperName(\##
"asyncOptionalChain");else this.resultCode+=this.helperManager.getHelperName("optionalChain");this.resultCode+="(["}\##
}appendTokenSuffix(){let e=this.currentToken();if(e.isOptionalChainEnd&&!this.disableESTransforms)this.resultCode+="\##
])";if(e.numNullishCoalesceEnds&&!this.disableESTransforms)for(let s=0;s<e.numNullishCoalesceEnds;s++)this.resultCod\##
e+="))"}appendCode(e){this.resultCode+=e}currentToken(){return this.tokens[this.tokenIndex]}currentTokenCode(){let e\##
=this.currentToken();return this.code.slice(e.start,e.end)}tokenAtRelativeIndex(e){return this.tokens[this.tokenInde\##
x+e]}currentIndex(){return this.tokenIndex}nextToken(){if(this.tokenIndex===this.tokens.length)throw Error("Unexpect\##
edly reached end of input.");this.tokenIndex++}previousToken(){this.tokenIndex--}finish(){if(this.tokenIndex!==this.\##
tokens.length)throw Error("Tried to finish processing tokens before reaching the end.");return this.resultCode+=this\##
.previousWhitespaceAndComments(),{code:this.resultCode,mappings:this.resultMappings}}isAtEnd(){return this.tokenInde\##
x===this.tokens.length}}function M1(e,s,r,o){let a=s.snapshot(),u=ql(s),m=[],x=[],k=[],T=null,y=[],C=[],L=s.currentT\##
oken().contextId;if(L==null)throw Error("Expected non-null class context ID on class open-brace.");s.nextToken();whi\##
le(!s.matchesContextIdAndLabel(t.braceR,L))if(s.matchesContextual(c._constructor)&&!s.currentToken().isType)({constr\##
uctorInitializerStatements:m,constructorInsertPos:T}=ei(s));else if(s.matches1(t.semi)){if(!o)C.push({start:s.curren\##
tIndex(),end:s.currentIndex()+1});s.nextToken()}else if(s.currentToken().isType)s.nextToken();else{let M=s.currentIn\##
dex(),z=!1,U=!1,I=!1;while(fs(s.currentToken())){if(s.matches1(t._static))z=!0;if(s.matches1(t.hash))U=!0;if(s.match\##
es1(t._declare)||s.matches1(t._abstract))I=!0;s.nextToken()}if(z&&s.matches1(t.braceL)){O1(s,L);continue}if(U){O1(s,\##
L);continue}if(s.matchesContextual(c._constructor)&&!s.currentToken().isType){({constructorInitializerStatements:m,c\##
onstructorInsertPos:T}=ei(s));continue}let N=s.currentIndex();if($l(s),s.matches1(t.lessThan)||s.matches1(t.parenL))\##
{O1(s,L);continue}while(s.currentToken().isType)s.nextToken();if(s.matches1(t.eq)){let P=s.currentIndex(),W=s.curren\##
tToken().rhsEndIndex;if(W==null)throw Error("Expected rhsEndIndex on class field assignment.");s.nextToken();while(s\##
.currentIndex()<W)e.processToken();let B;if(z)B=r.claimFreeName("__initStatic"),k.push(B);else B=r.claimFreeName("__\##
init"),x.push(B);y.push({initializerName:B,equalsIndex:P,start:N,end:s.currentIndex()})}else if(!o||I)C.push({start:\##
M,end:s.currentIndex()})}if(s.restoreToSnapshot(a),o)return{headerInfo:u,constructorInitializerStatements:m,instance\##
InitializerNames:[],staticInitializerNames:[],constructorInsertPos:T,fields:[],rangesToRemove:C};else return{headerI\##
nfo:u,constructorInitializerStatements:m,instanceInitializerNames:x,staticInitializerNames:k,constructorInsertPos:T,\##
fields:y,rangesToRemove:C}}function O1(e,s){e.nextToken();while(e.currentToken().contextId!==s)e.nextToken();while(f\##
s(e.tokenAtRelativeIndex(-1)))e.previousToken()}function ql(e){let s=e.currentToken(),r=s.contextId;if(r==null)throw\##
 Error("Expected context ID on class token.");let o=s.isExpression;if(o==null)throw Error("Expected isExpression on \##
class token.");let a=null,u=!1;if(e.nextToken(),e.matches1(t.name))a=e.identifierName();while(!e.matchesContextIdAnd\##
Label(t.braceL,r)){if(e.matches1(t._extends)&&!e.currentToken().isType)u=!0;e.nextToken()}return{isExpression:o,clas\##
sName:a,hasSuperclass:u}}function ei(e){let s=[];e.nextToken();let r=e.currentToken().contextId;if(r==null)throw Err\##
or("Expected context ID on open-paren starting constructor params.");while(!e.matchesContextIdAndLabel(t.parenR,r))i\##
f(e.currentToken().contextId===r){if(e.nextToken(),fs(e.currentToken())){e.nextToken();while(fs(e.currentToken()))e.\##
nextToken();let u=e.currentToken();if(u.type!==t.name)throw Error("Expected identifier after access modifiers in con\##
structor arg.");let m=e.identifierNameForToken(u);s.push(`this.${m} = ${m}`)}}else e.nextToken();e.nextToken();while\##
(e.currentToken().isType)e.nextToken();let o=e.currentIndex(),a=!1;while(!e.matchesContextIdAndLabel(t.braceR,r)){if\##
(!a&&e.matches2(t._super,t.parenL)){e.nextToken();let u=e.currentToken().contextId;if(u==null)throw Error("Expected \##
a context ID on the super call");while(!e.matchesContextIdAndLabel(t.parenR,u))e.nextToken();o=e.currentIndex(),a=!0\##
}e.nextToken()}return e.nextToken(),{constructorInitializerStatements:s,constructorInsertPos:o}}function fs(e){retur\##
n[t._async,t._get,t._set,t.plus,t.minus,t._readonly,t._static,t._public,t._private,t._protected,t._override,t._abstr\##
act,t.star,t._declare,t.hash].includes(e.type)}function $l(e){if(e.matches1(t.bracketL)){let r=e.currentToken().cont\##
extId;if(r==null)throw Error("Expected class context ID on computed name open bracket.");while(!e.matchesContextIdAn\##
dLabel(t.bracketR,r))e.nextToken();e.nextToken()}else e.nextToken()}function Rt(e){if(e.removeInitialToken(),e.remov\##
eToken(),e.removeToken(),e.removeToken(),e.matches1(t.parenL))e.removeToken(),e.removeToken(),e.removeToken();else w\##
hile(e.matches1(t.dot))e.removeToken(),e.removeToken()}var hs={typeDeclarations:new Set,valueDeclarations:new Set};f\##
unction vt(e){let s=new Set,r=new Set;for(let o=0;o<e.tokens.length;o++){let a=e.tokens[o];if(a.type===t.name&&qt(a)\##
)if(a.isType)s.add(e.identifierNameForToken(a));else r.add(e.identifierNameForToken(a))}return{typeDeclarations:s,va\##
lueDeclarations:r}}function Lt(e){let s=e.currentIndex();while(!e.matches1AtIndex(s,t.braceR))s++;return e.matchesCo\##
ntextualAtIndex(s+1,c._from)&&e.matches1AtIndex(s+2,t.string)}function Ae(e){if(e.matches2(t._with,t.braceL)||e.matc\##
hes2(t.name,t.braceL)&&e.matchesContextual(c._assert))e.removeToken(),e.removeToken(),e.removeBalancedCode(),e.remov\##
eToken()}function Dt(e,s,r,o){if(!e||s)return!1;let a=r.currentToken();if(a.rhsEndIndex==null)throw Error("Expected \##
non-null rhsEndIndex on export token.");let u=a.rhsEndIndex-r.currentIndex();if(u!==3&&!(u===4&&r.matches1AtIndex(a.\##
rhsEndIndex-1,t.semi)))return!1;let m=r.tokenAtRelativeIndex(2);if(m.type!==t.name)return!1;let x=r.identifierNameFo\##
rToken(m);return o.typeDeclarations.has(x)&&!o.valueDeclarations.has(x)}class Me extends G{__init(){this.hadExport=!\##
1}__init2(){this.hadNamedExport=!1}__init3(){this.hadDefaultExport=!1}constructor(e,s,r,o,a,u,m,x,k,T,y,C){super();t\##
his.rootTransformer=e,this.tokens=s,this.importProcessor=r,this.nameManager=o,this.helperManager=a,this.reactHotLoad\##
erTransformer=u,this.enableLegacyBabel5ModuleInterop=m,this.enableLegacyTypeScriptModuleInterop=x,this.isTypeScriptT\##
ransformEnabled=k,this.isFlowTransformEnabled=T,this.preserveDynamicImport=y,this.keepUnusedImports=C,Me.prototype._\##
_init.call(this),Me.prototype.__init2.call(this),Me.prototype.__init3.call(this),this.declarationInfo=k?vt(s):hs}get\##
PrefixCode(){let e="";if(this.hadExport)e+='Object.defineProperty(exports, "__esModule", {value: true});';return e}g\##
etSuffixCode(){if(this.enableLegacyBabel5ModuleInterop&&this.hadDefaultExport&&!this.hadNamedExport)return`
module.exports = exports.default;
`;return""}process(){if(this.tokens.matches3(t._import,t.name,t.eq))return this.processImportEquals();if(this.tokens\##
.matches1(t._import))return this.processImport(),!0;if(this.tokens.matches2(t._export,t.eq))return this.tokens.repla\##
ceToken("module.exports"),!0;if(this.tokens.matches1(t._export)&&!this.tokens.currentToken().isType)return this.hadE\##
xport=!0,this.processExport();if(this.tokens.matches2(t.name,t.postIncDec)){if(this.processPostIncDec())return!0}if(\##
this.tokens.matches1(t.name)||this.tokens.matches1(t.jsxName))return this.processIdentifier();if(this.tokens.matches\##
1(t.eq))return this.processAssignment();if(this.tokens.matches1(t.assign))return this.processComplexAssignment();if(\##
this.tokens.matches1(t.preIncDec))return this.processPreIncDec();return!1}processImportEquals(){let e=this.tokens.id\##
entifierNameAtIndex(this.tokens.currentIndex()+1);if(this.importProcessor.shouldAutomaticallyElideImportedName(e))Rt\##
(this.tokens);else this.tokens.replaceToken("const");return!0}processImport(){if(this.tokens.matches2(t._import,t.pa\##
renL)){if(this.preserveDynamicImport){this.tokens.copyToken();return}let s=this.enableLegacyTypeScriptModuleInterop?\##
"":`${this.helperManager.getHelperName("interopRequireWildcard")}(`;this.tokens.replaceToken(`Promise.resolve().then\##
(() => ${s}require`);let r=this.tokens.currentToken().contextId;if(r==null)throw Error("Expected context ID on dynam\##
ic import invocation.");this.tokens.copyToken();while(!this.tokens.matchesContextIdAndLabel(t.parenR,r))this.rootTra\##
nsformer.processToken();this.tokens.replaceToken(s?")))":"))");return}if(this.removeImportAndDetectIfShouldElide())t\##
his.tokens.removeToken();else{let s=this.tokens.stringValue();this.tokens.replaceTokenTrimmingLeftWhitespace(this.im\##
portProcessor.claimImportCode(s)),this.tokens.appendCode(this.importProcessor.claimImportCode(s))}if(Ae(this.tokens)\##
,this.tokens.matches1(t.semi))this.tokens.removeToken()}removeImportAndDetectIfShouldElide(){if(this.tokens.removeIn\##
itialToken(),this.tokens.matchesContextual(c._type)&&!this.tokens.matches1AtIndex(this.tokens.currentIndex()+1,t.com\##
ma)&&!this.tokens.matchesContextualAtIndex(this.tokens.currentIndex()+1,c._from))return this.removeRemainingImport()\##
,!0;if(this.tokens.matches1(t.name)||this.tokens.matches1(t.star))return this.removeRemainingImport(),!1;if(this.tok\##
ens.matches1(t.string))return!1;let e=!1,s=!1;while(!this.tokens.matches1(t.string)){if(!e&&this.tokens.matches1(t.b\##
raceL)||this.tokens.matches1(t.comma)){if(this.tokens.removeToken(),!this.tokens.matches1(t.braceR))s=!0;if(this.tok\##
ens.matches2(t.name,t.comma)||this.tokens.matches2(t.name,t.braceR)||this.tokens.matches4(t.name,t.name,t.name,t.com\##
ma)||this.tokens.matches4(t.name,t.name,t.name,t.braceR))e=!0}this.tokens.removeToken()}if(this.keepUnusedImports)re\##
turn!1;if(this.isTypeScriptTransformEnabled)return!e;else if(this.isFlowTransformEnabled)return s&&!e;else return!1}\##
removeRemainingImport(){while(!this.tokens.matches1(t.string))this.tokens.removeToken()}processIdentifier(){let e=th\##
is.tokens.currentToken();if(e.shadowsGlobal)return!1;if(e.identifierRole===_.ObjectShorthand)return this.processObje\##
ctShorthand();if(e.identifierRole!==_.Access)return!1;let s=this.importProcessor.getIdentifierReplacement(this.token\##
s.identifierNameForToken(e));if(!s)return!1;let r=this.tokens.currentIndex()+1;while(r<this.tokens.tokens.length&&th\##
is.tokens.tokens[r].type===t.parenR)r++;if(this.tokens.tokens[r].type===t.parenL)if(this.tokens.tokenAtRelativeIndex\##
(1).type===t.parenL&&this.tokens.tokenAtRelativeIndex(-1).type!==t._new)this.tokens.replaceToken(`${s}.call(void 0, \##
`),this.tokens.removeToken(),this.rootTransformer.processBalancedCode(),this.tokens.copyExpectedToken(t.parenR);else\##
 this.tokens.replaceToken(`(0, ${s})`);else this.tokens.replaceToken(s);return!0}processObjectShorthand(){let e=this\##
.tokens.identifierName(),s=this.importProcessor.getIdentifierReplacement(e);if(!s)return!1;return this.tokens.replac\##
eToken(`${e}: ${s}`),!0}processExport(){if(this.tokens.matches2(t._export,t._enum)||this.tokens.matches3(t._export,t\##
._const,t._enum))return this.hadNamedExport=!0,!1;if(this.tokens.matches2(t._export,t._default)){if(this.tokens.matc\##
hes3(t._export,t._default,t._enum))return this.hadDefaultExport=!0,!1;return this.processExportDefault(),!0}else if(\##
this.tokens.matches2(t._export,t.braceL))return this.processExportBindings(),!0;else if(this.tokens.matches2(t._expo\##
rt,t.name)&&this.tokens.matchesContextualAtIndex(this.tokens.currentIndex()+1,c._type)){if(this.tokens.removeInitial\##
Token(),this.tokens.removeToken(),this.tokens.matches1(t.braceL)){while(!this.tokens.matches1(t.braceR))this.tokens.\##
removeToken();this.tokens.removeToken()}else if(this.tokens.removeToken(),this.tokens.matches1(t._as))this.tokens.re\##
moveToken(),this.tokens.removeToken();if(this.tokens.matchesContextual(c._from)&&this.tokens.matches1AtIndex(this.to\##
kens.currentIndex()+1,t.string))this.tokens.removeToken(),this.tokens.removeToken(),Ae(this.tokens);return!0}if(this\##
.hadNamedExport=!0,this.tokens.matches2(t._export,t._var)||this.tokens.matches2(t._export,t._let)||this.tokens.match\##
es2(t._export,t._const))return this.processExportVar(),!0;else if(this.tokens.matches2(t._export,t._function)||this.\##
tokens.matches3(t._export,t.name,t._function))return this.processExportFunction(),!0;else if(this.tokens.matches2(t.\##
_export,t._class)||this.tokens.matches3(t._export,t._abstract,t._class)||this.tokens.matches2(t._export,t.at))return\##
 this.processExportClass(),!0;else if(this.tokens.matches2(t._export,t.star))return this.processExportStar(),!0;else\##
 throw Error("Unrecognized export syntax.")}processAssignment(){let e=this.tokens.currentIndex(),s=this.tokens.token\##
s[e-1];if(s.isType||s.type!==t.name)return!1;if(s.shadowsGlobal)return!1;if(e>=2&&this.tokens.matches1AtIndex(e-2,t.\##
dot))return!1;if(e>=2&&[t._var,t._let,t._const].includes(this.tokens.tokens[e-2].type))return!1;let r=this.importPro\##
cessor.resolveExportBinding(this.tokens.identifierNameForToken(s));if(!r)return!1;return this.tokens.copyToken(),thi\##
s.tokens.appendCode(` ${r} =`),!0}processComplexAssignment(){let e=this.tokens.currentIndex(),s=this.tokens.tokens[e\##
-1];if(s.type!==t.name)return!1;if(s.shadowsGlobal)return!1;if(e>=2&&this.tokens.matches1AtIndex(e-2,t.dot))return!1\##
;let r=this.importProcessor.resolveExportBinding(this.tokens.identifierNameForToken(s));if(!r)return!1;return this.t\##
okens.appendCode(` = ${r}`),this.tokens.copyToken(),!0}processPreIncDec(){let e=this.tokens.currentIndex(),s=this.to\##
kens.tokens[e+1];if(s.type!==t.name)return!1;if(s.shadowsGlobal)return!1;if(e+2<this.tokens.tokens.length&&(this.tok\##
ens.matches1AtIndex(e+2,t.dot)||this.tokens.matches1AtIndex(e+2,t.bracketL)||this.tokens.matches1AtIndex(e+2,t.paren\##
L)))return!1;let r=this.tokens.identifierNameForToken(s),o=this.importProcessor.resolveExportBinding(r);if(!o)return\##
!1;return this.tokens.appendCode(`${o} = `),this.tokens.copyToken(),!0}processPostIncDec(){let e=this.tokens.current\##
Index(),s=this.tokens.tokens[e],r=this.tokens.tokens[e+1];if(s.type!==t.name)return!1;if(s.shadowsGlobal)return!1;if\##
(e>=1&&this.tokens.matches1AtIndex(e-1,t.dot))return!1;let o=this.tokens.identifierNameForToken(s),a=this.importProc\##
essor.resolveExportBinding(o);if(!a)return!1;let u=this.tokens.rawCodeForToken(r),m=this.importProcessor.getIdentifi\##
erReplacement(o)||o;if(u==="++")this.tokens.replaceToken(`(${m} = ${a} = ${m} + 1, ${m} - 1)`);else if(u==="--")this\##
.tokens.replaceToken(`(${m} = ${a} = ${m} - 1, ${m} + 1)`);else throw Error(`Unexpected operator: ${u}`);return this\##
.tokens.removeToken(),!0}processExportDefault(){let e=!0;if(this.tokens.matches4(t._export,t._default,t._function,t.\##
name)||this.tokens.matches5(t._export,t._default,t.name,t._function,t.name)&&this.tokens.matchesContextualAtIndex(th\##
is.tokens.currentIndex()+2,c._async)){this.tokens.removeInitialToken(),this.tokens.removeToken();let s=this.processN\##
amedFunction();this.tokens.appendCode(` exports.default = ${s};`)}else if(this.tokens.matches4(t._export,t._default,\##
t._class,t.name)||this.tokens.matches5(t._export,t._default,t._abstract,t._class,t.name)||this.tokens.matches3(t._ex\##
port,t._default,t.at)){if(this.tokens.removeInitialToken(),this.tokens.removeToken(),this.copyDecorators(),this.toke\##
ns.matches1(t._abstract))this.tokens.removeToken();let s=this.rootTransformer.processNamedClass();this.tokens.append\##
Code(` exports.default = ${s};`)}else if(Dt(this.isTypeScriptTransformEnabled,this.keepUnusedImports,this.tokens,thi\##
s.declarationInfo))e=!1,this.tokens.removeInitialToken(),this.tokens.removeToken(),this.tokens.removeToken();else if\##
(this.reactHotLoaderTransformer){let s=this.nameManager.claimFreeName("_default");this.tokens.replaceToken(`let ${s}\##
; exports.`),this.tokens.copyToken(),this.tokens.appendCode(` = ${s} =`),this.reactHotLoaderTransformer.setExtracted\##
DefaultExportName(s)}else this.tokens.replaceToken("exports."),this.tokens.copyToken(),this.tokens.appendCode(" =");\##
if(e)this.hadDefaultExport=!0}copyDecorators(){while(this.tokens.matches1(t.at))if(this.tokens.copyToken(),this.toke\##
ns.matches1(t.parenL))this.tokens.copyExpectedToken(t.parenL),this.rootTransformer.processBalancedCode(),this.tokens\##
.copyExpectedToken(t.parenR);else{this.tokens.copyExpectedToken(t.name);while(this.tokens.matches1(t.dot))this.token\##
s.copyExpectedToken(t.dot),this.tokens.copyExpectedToken(t.name);if(this.tokens.matches1(t.parenL))this.tokens.copyE\##
xpectedToken(t.parenL),this.rootTransformer.processBalancedCode(),this.tokens.copyExpectedToken(t.parenR)}}processEx\##
portVar(){if(this.isSimpleExportVar())this.processSimpleExportVar();else this.processComplexExportVar()}isSimpleExpo\##
rtVar(){let e=this.tokens.currentIndex();if(e++,e++,!this.tokens.matches1AtIndex(e,t.name))return!1;e++;while(e<this\##
.tokens.tokens.length&&this.tokens.tokens[e].isType)e++;if(!this.tokens.matches1AtIndex(e,t.eq))return!1;return!0}pr\##
ocessSimpleExportVar(){this.tokens.removeInitialToken(),this.tokens.copyToken();let e=this.tokens.identifierName();w\##
hile(!this.tokens.matches1(t.eq))this.rootTransformer.processToken();let s=this.tokens.currentToken().rhsEndIndex;if\##
(s==null)throw Error("Expected = token with an end index.");while(this.tokens.currentIndex()<s)this.rootTransformer.\##
processToken();this.tokens.appendCode(`; exports.${e} = ${e}`)}processComplexExportVar(){this.tokens.removeInitialTo\##
ken(),this.tokens.removeToken();let e=this.tokens.matches1(t.braceL);if(e)this.tokens.appendCode("(");let s=0;while(\##
!0)if(this.tokens.matches1(t.braceL)||this.tokens.matches1(t.dollarBraceL)||this.tokens.matches1(t.bracketL))s++,thi\##
s.tokens.copyToken();else if(this.tokens.matches1(t.braceR)||this.tokens.matches1(t.bracketR))s--,this.tokens.copyTo\##
ken();else if(s===0&&!this.tokens.matches1(t.name)&&!this.tokens.currentToken().isType)break;else if(this.tokens.mat\##
ches1(t.eq)){let r=this.tokens.currentToken().rhsEndIndex;if(r==null)throw Error("Expected = token with an end index\##
.");while(this.tokens.currentIndex()<r)this.rootTransformer.processToken()}else{let r=this.tokens.currentToken();if(\##
jt(r)){let o=this.tokens.identifierName(),a=this.importProcessor.getIdentifierReplacement(o);if(a===null)throw Error\##
(`Expected a replacement for ${o} in \`export var\` syntax.`);if(Y1(r))a=`${o}: ${a}`;this.tokens.replaceToken(a)}el\##
se this.rootTransformer.processToken()}if(e){let r=this.tokens.currentToken().rhsEndIndex;if(r==null)throw Error("Ex\##
pected = token with an end index.");while(this.tokens.currentIndex()<r)this.rootTransformer.processToken();this.toke\##
ns.appendCode(")")}}processExportFunction(){this.tokens.replaceToken("");let e=this.processNamedFunction();this.toke\##
ns.appendCode(` exports.${e} = ${e};`)}processNamedFunction(){if(this.tokens.matches1(t._function))this.tokens.copyT\##
oken();else if(this.tokens.matches2(t.name,t._function)){if(!this.tokens.matchesContextual(c._async))throw Error("Ex\##
pected async keyword in function export.");this.tokens.copyToken(),this.tokens.copyToken()}if(this.tokens.matches1(t\##
.star))this.tokens.copyToken();if(!this.tokens.matches1(t.name))throw Error("Expected identifier for exported functi\##
on name.");let e=this.tokens.identifierName();if(this.tokens.copyToken(),this.tokens.currentToken().isType){this.tok\##
ens.removeInitialToken();while(this.tokens.currentToken().isType)this.tokens.removeToken()}return this.tokens.copyEx\##
pectedToken(t.parenL),this.rootTransformer.processBalancedCode(),this.tokens.copyExpectedToken(t.parenR),this.rootTr\##
ansformer.processPossibleTypeRange(),this.tokens.copyExpectedToken(t.braceL),this.rootTransformer.processBalancedCod\##
e(),this.tokens.copyExpectedToken(t.braceR),e}processExportClass(){if(this.tokens.removeInitialToken(),this.copyDeco\##
rators(),this.tokens.matches1(t._abstract))this.tokens.removeToken();let e=this.rootTransformer.processNamedClass();\##
this.tokens.appendCode(` exports.${e} = ${e};`)}processExportBindings(){this.tokens.removeInitialToken(),this.tokens\##
.removeToken();let e=Lt(this.tokens),s=[];while(!0){if(this.tokens.matches1(t.braceR)){this.tokens.removeToken();bre\##
ak}let r=ke(this.tokens);while(this.tokens.currentIndex()<r.endIndex)this.tokens.removeToken();if(!(r.isType||!e&&th\##
is.shouldElideExportedIdentifier(r.leftName))){let a=r.rightName;if(a==="default")this.hadDefaultExport=!0;else this\##
.hadNamedExport=!0;let u=r.leftName,m=this.importProcessor.getIdentifierReplacement(u);s.push(`exports.${a} = ${m||u\##
};`)}if(this.tokens.matches1(t.braceR)){this.tokens.removeToken();break}if(this.tokens.matches2(t.comma,t.braceR)){t\##
his.tokens.removeToken(),this.tokens.removeToken();break}else if(this.tokens.matches1(t.comma))this.tokens.removeTok\##
en();else throw Error(`Unexpected token: ${JSON.stringify(this.tokens.currentToken())}`)}if(this.tokens.matchesConte\##
xtual(c._from)){this.tokens.removeToken();let r=this.tokens.stringValue();this.tokens.replaceTokenTrimmingLeftWhites\##
pace(this.importProcessor.claimImportCode(r)),Ae(this.tokens)}else this.tokens.appendCode(s.join(" "));if(this.token\##
s.matches1(t.semi))this.tokens.removeToken()}processExportStar(){this.tokens.removeInitialToken();while(!this.tokens\##
.matches1(t.string))this.tokens.removeToken();let e=this.tokens.stringValue();if(this.tokens.replaceTokenTrimmingLef\##
tWhitespace(this.importProcessor.claimImportCode(e)),Ae(this.tokens),this.tokens.matches1(t.semi))this.tokens.remove\##
Token()}shouldElideExportedIdentifier(e){return this.isTypeScriptTransformEnabled&&!this.keepUnusedImports&&!this.de\##
clarationInfo.valueDeclarations.has(e)}}class ms extends G{constructor(e,s,r,o,a,u,m,x){super();this.tokens=e,this.n\##
ameManager=s,this.helperManager=r,this.reactHotLoaderTransformer=o,this.isTypeScriptTransformEnabled=a,this.isFlowTr\##
ansformEnabled=u,this.keepUnusedImports=m,this.nonTypeIdentifiers=a&&!m?Wt(e,x):new Set,this.declarationInfo=a&&!m?v\##
t(e):hs,this.injectCreateRequireForImportRequire=Boolean(x.injectCreateRequireForImportRequire)}process(){if(this.to\##
kens.matches3(t._import,t.name,t.eq))return this.processImportEquals();if(this.tokens.matches4(t._import,t.name,t.na\##
me,t.eq)&&this.tokens.matchesContextualAtIndex(this.tokens.currentIndex()+1,c._type)){this.tokens.removeInitialToken\##
();for(let e=0;e<7;e++)this.tokens.removeToken();return!0}if(this.tokens.matches2(t._export,t.eq))return this.tokens\##
.replaceToken("module.exports"),!0;if(this.tokens.matches5(t._export,t._import,t.name,t.name,t.eq)&&this.tokens.matc\##
hesContextualAtIndex(this.tokens.currentIndex()+2,c._type)){this.tokens.removeInitialToken();for(let e=0;e<8;e++)thi\##
s.tokens.removeToken();return!0}if(this.tokens.matches1(t._import))return this.processImport();if(this.tokens.matche\##
s2(t._export,t._default))return this.processExportDefault();if(this.tokens.matches2(t._export,t.braceL))return this.\##
processNamedExports();if(this.tokens.matches2(t._export,t.name)&&this.tokens.matchesContextualAtIndex(this.tokens.cu\##
rrentIndex()+1,c._type)){if(this.tokens.removeInitialToken(),this.tokens.removeToken(),this.tokens.matches1(t.braceL\##
)){while(!this.tokens.matches1(t.braceR))this.tokens.removeToken();this.tokens.removeToken()}else if(this.tokens.rem\##
oveToken(),this.tokens.matches1(t._as))this.tokens.removeToken(),this.tokens.removeToken();if(this.tokens.matchesCon\##
textual(c._from)&&this.tokens.matches1AtIndex(this.tokens.currentIndex()+1,t.string))this.tokens.removeToken(),this.\##
tokens.removeToken(),Ae(this.tokens);return!0}return!1}processImportEquals(){let e=this.tokens.identifierNameAtIndex\##
(this.tokens.currentIndex()+1);if(this.shouldAutomaticallyElideImportedName(e))Rt(this.tokens);else if(this.injectCr\##
eateRequireForImportRequire)this.tokens.replaceToken("const"),this.tokens.copyToken(),this.tokens.copyToken(),this.t\##
okens.replaceToken(this.helperManager.getHelperName("require"));else this.tokens.replaceToken("const");return!0}proc\##
essImport(){if(this.tokens.matches2(t._import,t.parenL))return!1;let e=this.tokens.snapshot();if(this.removeImportTy\##
peBindings()){this.tokens.restoreToSnapshot(e);while(!this.tokens.matches1(t.string))this.tokens.removeToken();if(th\##
is.tokens.removeToken(),Ae(this.tokens),this.tokens.matches1(t.semi))this.tokens.removeToken()}return!0}removeImport\##
TypeBindings(){if(this.tokens.copyExpectedToken(t._import),this.tokens.matchesContextual(c._type)&&!this.tokens.matc\##
hes1AtIndex(this.tokens.currentIndex()+1,t.comma)&&!this.tokens.matchesContextualAtIndex(this.tokens.currentIndex()+\##
1,c._from))return!0;if(this.tokens.matches1(t.string))return this.tokens.copyToken(),!1;if(this.tokens.matchesContex\##
tual(c._module)&&this.tokens.matchesContextualAtIndex(this.tokens.currentIndex()+2,c._from))this.tokens.copyToken();\##
let e=!1,s=!1,r=!1;if(this.tokens.matches1(t.name)){if(this.shouldAutomaticallyElideImportedName(this.tokens.identif\##
ierName())){if(this.tokens.removeToken(),this.tokens.matches1(t.comma))this.tokens.removeToken()}else if(e=!0,this.t\##
okens.copyToken(),this.tokens.matches1(t.comma))r=!0,this.tokens.removeToken()}if(this.tokens.matches1(t.star))if(th\##
is.shouldAutomaticallyElideImportedName(this.tokens.identifierNameAtRelativeIndex(2)))this.tokens.removeToken(),this\##
.tokens.removeToken(),this.tokens.removeToken();else{if(r)this.tokens.appendCode(",");e=!0,this.tokens.copyExpectedT\##
oken(t.star),this.tokens.copyExpectedToken(t.name),this.tokens.copyExpectedToken(t.name)}else if(this.tokens.matches\##
1(t.braceL)){if(r)this.tokens.appendCode(",");this.tokens.copyToken();while(!this.tokens.matches1(t.braceR)){s=!0;le\##
t o=ke(this.tokens);if(o.isType||this.shouldAutomaticallyElideImportedName(o.rightName)){while(this.tokens.currentIn\##
dex()<o.endIndex)this.tokens.removeToken();if(this.tokens.matches1(t.comma))this.tokens.removeToken()}else{e=!0;whil\##
e(this.tokens.currentIndex()<o.endIndex)this.tokens.copyToken();if(this.tokens.matches1(t.comma))this.tokens.copyTok\##
en()}}this.tokens.copyExpectedToken(t.braceR)}if(this.keepUnusedImports)return!1;if(this.isTypeScriptTransformEnable\##
d)return!e;else if(this.isFlowTransformEnabled)return s&&!e;else return!1}shouldAutomaticallyElideImportedName(e){re\##
turn this.isTypeScriptTransformEnabled&&!this.keepUnusedImports&&!this.nonTypeIdentifiers.has(e)}processExportDefaul\##
t(){if(Dt(this.isTypeScriptTransformEnabled,this.keepUnusedImports,this.tokens,this.declarationInfo))return this.tok\##
ens.removeInitialToken(),this.tokens.removeToken(),this.tokens.removeToken(),!0;if(!(this.tokens.matches4(t._export,\##
t._default,t._function,t.name)||this.tokens.matches5(t._export,t._default,t.name,t._function,t.name)&&this.tokens.ma\##
tchesContextualAtIndex(this.tokens.currentIndex()+2,c._async)||this.tokens.matches4(t._export,t._default,t._class,t.\##
name)||this.tokens.matches5(t._export,t._default,t._abstract,t._class,t.name))&&this.reactHotLoaderTransformer){let \##
s=this.nameManager.claimFreeName("_default");return this.tokens.replaceToken(`let ${s}; export`),this.tokens.copyTok\##
en(),this.tokens.appendCode(` ${s} =`),this.reactHotLoaderTransformer.setExtractedDefaultExportName(s),!0}return!1}p\##
rocessNamedExports(){if(!this.isTypeScriptTransformEnabled)return!1;this.tokens.copyExpectedToken(t._export),this.to\##
kens.copyExpectedToken(t.braceL);let e=Lt(this.tokens),s=!1;while(!this.tokens.matches1(t.braceR)){let r=ke(this.tok\##
ens);if(r.isType||!e&&this.shouldElideExportedName(r.leftName)){while(this.tokens.currentIndex()<r.endIndex)this.tok\##
ens.removeToken();if(this.tokens.matches1(t.comma))this.tokens.removeToken()}else{s=!0;while(this.tokens.currentInde\##
x()<r.endIndex)this.tokens.copyToken();if(this.tokens.matches1(t.comma))this.tokens.copyToken()}}if(this.tokens.copy\##
ExpectedToken(t.braceR),!this.keepUnusedImports&&e&&!s)this.tokens.removeToken(),this.tokens.removeToken(),Ae(this.t\##
okens);return!0}shouldElideExportedName(e){return this.isTypeScriptTransformEnabled&&!this.keepUnusedImports&&this.d\##
eclarationInfo.typeDeclarations.has(e)&&!this.declarationInfo.valueDeclarations.has(e)}}class ds extends G{construct\##
or(e,s,r){super();this.rootTransformer=e,this.tokens=s,this.isImportsTransformEnabled=r}process(){if(this.rootTransf\##
ormer.processPossibleArrowParamEnd()||this.rootTransformer.processPossibleAsyncArrowWithTypeParams()||this.rootTrans\##
former.processPossibleTypeRange())return!0;if(this.tokens.matches1(t._enum))return this.processEnum(),!0;if(this.tok\##
ens.matches2(t._export,t._enum))return this.processNamedExportEnum(),!0;if(this.tokens.matches3(t._export,t._default\##
,t._enum))return this.processDefaultExportEnum(),!0;return!1}processNamedExportEnum(){if(this.isImportsTransformEnab\##
led){this.tokens.removeInitialToken();let e=this.tokens.identifierNameAtRelativeIndex(1);this.processEnum(),this.tok\##
ens.appendCode(` exports.${e} = ${e};`)}else this.tokens.copyToken(),this.processEnum()}processDefaultExportEnum(){t\##
his.tokens.removeInitialToken(),this.tokens.removeToken();let e=this.tokens.identifierNameAtRelativeIndex(1);if(this\##
.processEnum(),this.isImportsTransformEnabled)this.tokens.appendCode(` exports.default = ${e};`);else this.tokens.ap\##
pendCode(` export default ${e};`)}processEnum(){this.tokens.replaceToken("const"),this.tokens.copyExpectedToken(t.na\##
me);let e=!1;if(this.tokens.matchesContextual(c._of))this.tokens.removeToken(),e=this.tokens.matchesContextual(c._sy\##
mbol),this.tokens.removeToken();let s=this.tokens.matches3(t.braceL,t.name,t.eq);this.tokens.appendCode(' = require(\##
"flow-enums-runtime")');let r=!e&&!s;this.tokens.replaceTokenTrimmingLeftWhitespace(r?".Mirrored([":"({");while(!thi\##
s.tokens.matches1(t.braceR)){if(this.tokens.matches1(t.ellipsis)){this.tokens.removeToken();break}if(this.processEnu\##
mElement(e,s),this.tokens.matches1(t.comma))this.tokens.copyToken()}this.tokens.replaceToken(r?"]);":"});")}processE\##
numElement(e,s){if(e){let r=this.tokens.identifierName();this.tokens.copyToken(),this.tokens.appendCode(`: Symbol("$\##
{r}")`)}else if(s)this.tokens.copyToken(),this.tokens.replaceTokenTrimmingLeftWhitespace(":"),this.tokens.copyToken(\##
);else this.tokens.replaceToken(`"${this.tokens.identifierName()}"`)}}function Hl(e){let s=void 0,r=e[0],o=1;while(o\##
<e.length){let a=e[o],u=e[o+1];if(o+=2,(a==="optionalAccess"||a==="optionalCall")&&r==null)return;if(a==="access"||a\##
==="optionalAccess")s=r,r=u(r);else if(a==="call"||a==="optionalCall")r=u((...m)=>r.call(s,...m)),s=void 0}return r}\##
var ks="jest",Ul=["mock","unmock","enableAutomock","disableAutomock"];class Ft extends G{__init(){this.hoistedFuncti\##
onNames=[]}constructor(e,s,r,o){super();this.rootTransformer=e,this.tokens=s,this.nameManager=r,this.importProcessor\##
=o,Ft.prototype.__init.call(this)}process(){if(this.tokens.currentToken().scopeDepth===0&&this.tokens.matches4(t.nam\##
e,t.dot,t.name,t.parenL)&&this.tokens.identifierName()===ks){if(Hl([this,"access",(e)=>e.importProcessor,"optionalAc\##
cess",(e)=>e.getGlobalNames,"call",(e)=>e(),"optionalAccess",(e)=>e.has,"call",(e)=>e(ks)]))return!1;return this.ext\##
ractHoistedCalls()}return!1}getHoistedCode(){if(this.hoistedFunctionNames.length>0)return this.hoistedFunctionNames.\##
map((e)=>`${e}();`).join("");return""}extractHoistedCalls(){this.tokens.removeToken();let e=!1;while(this.tokens.mat\##
ches3(t.dot,t.name,t.parenL)){let s=this.tokens.identifierNameAtIndex(this.tokens.currentIndex()+1);if(Ul.includes(s\##
)){let o=this.nameManager.claimFreeName("__jestHoist");this.hoistedFunctionNames.push(o),this.tokens.replaceToken(`f\##
unction ${o}(){${ks}.`),this.tokens.copyToken(),this.tokens.copyToken(),this.rootTransformer.processBalancedCode(),t\##
his.tokens.copyExpectedToken(t.parenR),this.tokens.appendCode(";}"),e=!1}else{if(e)this.tokens.copyToken();else this\##
.tokens.replaceToken(`${ks}.`);this.tokens.copyToken(),this.tokens.copyToken(),this.rootTransformer.processBalancedC\##
ode(),this.tokens.copyExpectedToken(t.parenR),e=!0}}return!0}}class xs extends G{constructor(e){super();this.tokens=\##
e}process(){if(this.tokens.matches1(t.num)){let e=this.tokens.currentTokenCode();if(e.includes("_"))return this.toke\##
ns.replaceToken(e.replace(/_/g,"")),!0}return!1}}class gs extends G{constructor(e,s){super();this.tokens=e,this.name\##
Manager=s}process(){if(this.tokens.matches2(t._catch,t.braceL))return this.tokens.copyToken(),this.tokens.appendCode\##
(` (${this.nameManager.claimFreeName("e")})`),!0;return!1}}class _s extends G{constructor(e,s){super();this.tokens=e\##
,this.nameManager=s}process(){if(this.tokens.matches1(t.nullishCoalescing)){let r=this.tokens.currentToken();if(this\##
.tokens.tokens[r.nullishStartIndex].isAsyncOperation)this.tokens.replaceTokenTrimmingLeftWhitespace(", async () => (\##
");else this.tokens.replaceTokenTrimmingLeftWhitespace(", () => (");return!0}if(this.tokens.matches1(t._delete)){if(\##
this.tokens.tokenAtRelativeIndex(1).isOptionalChainStart)return this.tokens.removeInitialToken(),!0}let s=this.token\##
s.currentToken().subscriptStartIndex;if(s!=null&&this.tokens.tokens[s].isOptionalChainStart&&this.tokens.tokenAtRela\##
tiveIndex(-1).type!==t._super){let r=this.nameManager.claimFreeName("_"),o;if(s>0&&this.tokens.matches1AtIndex(s-1,t\##
._delete)&&this.isLastSubscriptInChain())o=`${r} => delete ${r}`;else o=`${r} => ${r}`;if(this.tokens.tokens[s].isAs\##
yncOperation)o=`async ${o}`;if(this.tokens.matches2(t.questionDot,t.parenL)||this.tokens.matches2(t.questionDot,t.le\##
ssThan)){if(this.justSkippedSuper())this.tokens.appendCode(".bind(this)");this.tokens.replaceTokenTrimmingLeftWhites\##
pace(`, 'optionalCall', ${o}`)}else if(this.tokens.matches2(t.questionDot,t.bracketL))this.tokens.replaceTokenTrimmi\##
ngLeftWhitespace(`, 'optionalAccess', ${o}`);else if(this.tokens.matches1(t.questionDot))this.tokens.replaceTokenTri\##
mmingLeftWhitespace(`, 'optionalAccess', ${o}.`);else if(this.tokens.matches1(t.dot))this.tokens.replaceTokenTrimmin\##
gLeftWhitespace(`, 'access', ${o}.`);else if(this.tokens.matches1(t.bracketL))this.tokens.replaceTokenTrimmingLeftWh\##
itespace(`, 'access', ${o}[`);else if(this.tokens.matches1(t.parenL)){if(this.justSkippedSuper())this.tokens.appendC\##
ode(".bind(this)");this.tokens.replaceTokenTrimmingLeftWhitespace(`, 'call', ${o}(`)}else throw Error("Unexpected su\##
bscript operator in optional chain.");return!0}return!1}isLastSubscriptInChain(){let e=0;for(let s=this.tokens.curre\##
ntIndex()+1;;s++){if(s>=this.tokens.tokens.length)throw Error("Reached the end of the code while finding the end of \##
the access chain.");if(this.tokens.tokens[s].isOptionalChainStart)e++;else if(this.tokens.tokens[s].isOptionalChainE\##
nd)e--;if(e<0)return!0;if(e===0&&this.tokens.tokens[s].subscriptStartIndex!=null)return!1}}justSkippedSuper(){let e=\##
0,s=this.tokens.currentIndex()-1;while(!0){if(s<0)throw Error("Reached the start of the code while finding the start\##
 of the access chain.");if(this.tokens.tokens[s].isOptionalChainStart)e--;else if(this.tokens.tokens[s].isOptionalCh\##
ainEnd)e++;if(e<0)return!1;if(e===0&&this.tokens.tokens[s].subscriptStartIndex!=null)return this.tokens.tokens[s-1].\##
type===t._super;s--}}}class Is extends G{constructor(e,s,r,o){super();this.rootTransformer=e,this.tokens=s,this.impo\##
rtProcessor=r,this.options=o}process(){let e=this.tokens.currentIndex();if(this.tokens.identifierName()==="createRea\##
ctClass"){let s=this.importProcessor&&this.importProcessor.getIdentifierReplacement("createReactClass");if(s)this.to\##
kens.replaceToken(`(0, ${s})`);else this.tokens.copyToken();return this.tryProcessCreateClassCall(e),!0}if(this.toke\##
ns.matches3(t.name,t.dot,t.name)&&this.tokens.identifierName()==="React"&&this.tokens.identifierNameAtIndex(this.tok\##
ens.currentIndex()+2)==="createClass"){let s=this.importProcessor?this.importProcessor.getIdentifierReplacement("Rea\##
ct")||"React":"React";if(s)this.tokens.replaceToken(s),this.tokens.copyToken(),this.tokens.copyToken();else this.tok\##
ens.copyToken(),this.tokens.copyToken(),this.tokens.copyToken();return this.tryProcessCreateClassCall(e),!0}return!1\##
}tryProcessCreateClassCall(e){let s=this.findDisplayName(e);if(!s)return;if(this.classNeedsDisplayName())this.tokens\##
.copyExpectedToken(t.parenL),this.tokens.copyExpectedToken(t.braceL),this.tokens.appendCode(`displayName: '${s}',`),\##
this.rootTransformer.processBalancedCode(),this.tokens.copyExpectedToken(t.braceR),this.tokens.copyExpectedToken(t.p\##
arenR)}findDisplayName(e){if(e<2)return null;if(this.tokens.matches2AtIndex(e-2,t.name,t.eq))return this.tokens.iden\##
tifierNameAtIndex(e-2);if(e>=2&&this.tokens.tokens[e-2].identifierRole===_.ObjectKey)return this.tokens.identifierNa\##
meAtIndex(e-2);if(this.tokens.matches2AtIndex(e-2,t._export,t._default))return this.getDisplayNameFromFilename();ret\##
urn null}getDisplayNameFromFilename(){let s=(this.options.filePath||"unknown").split("/"),r=s[s.length-1],o=r.lastIn\##
dexOf("."),a=o===-1?r:r.slice(0,o);if(a==="index"&&s[s.length-2])return s[s.length-2];else return a}classNeedsDispla\##
yName(){let e=this.tokens.currentIndex();if(!this.tokens.matches2(t.parenL,t.braceL))return!1;let s=e+1,r=this.token\##
s.tokens[s].contextId;if(r==null)throw Error("Expected non-null context ID on object open-brace.");for(;e<this.token\##
s.tokens.length;e++){let o=this.tokens.tokens[e];if(o.type===t.braceR&&o.contextId===r){e++;break}if(this.tokens.ide\##
ntifierNameAtIndex(e)==="displayName"&&this.tokens.tokens[e].identifierRole===_.ObjectKey&&o.contextId===r)return!1}\##
if(e===this.tokens.tokens.length)throw Error("Unexpected end of input when processing React class.");return this.tok\##
ens.matches1AtIndex(e,t.parenR)||this.tokens.matches2AtIndex(e,t.comma,t.parenR)}}class Ot extends G{__init(){this.e\##
xtractedDefaultExportName=null}constructor(e,s){super();this.tokens=e,this.filePath=s,Ot.prototype.__init.call(this)\##
}setExtractedDefaultExportName(e){this.extractedDefaultExportName=e}getPrefixCode(){return`
      (function () {
        var enterModule = require('react-hot-loader').enterModule;
        enterModule && enterModule(module);
      })();`.replace(/\s+/g," ").trim()}getSuffixCode(){let e=new Set;for(let r of this.tokens.tokens)if(!r.isType&&\##
qt(r)&&r.identifierRole!==_.ImportDeclaration)e.add(this.tokens.identifierNameForToken(r));let s=Array.from(e).map((\##
r)=>({variableName:r,uniqueLocalName:r}));if(this.extractedDefaultExportName)s.push({variableName:this.extractedDefa\##
ultExportName,uniqueLocalName:"default"});return`
;(function () {
  var reactHotLoader = require('react-hot-loader').default;
  var leaveModule = require('react-hot-loader').leaveModule;
  if (!reactHotLoader) {
    return;
  }
${s.map(({variableName:r,uniqueLocalName:o})=>`  reactHotLoader.register(${r}, "${o}", ${JSON.stringify(this.filePat\##
h||"")});`).join(`
`)}
  leaveModule(module);
})();`}process(){return!1}}var Wl=new Set(["break","case","catch","class","const","continue","debugger","default","d\##
elete","do","else","export","extends","finally","for","function","if","import","in","instanceof","new","return","sup\##
er","switch","this","throw","try","typeof","var","void","while","with","yield","enum","implements","interface","let"\##
,"package","private","protected","public","static","await","false","null","true"]);function ys(e){if(e.length===0)re\##
turn!1;if(!_e[e.charCodeAt(0)])return!1;for(let s=1;s<e.length;s++)if(!ee[e.charCodeAt(s)])return!1;return!Wl.has(e)\##
}class Ts extends G{constructor(e,s,r){super();this.rootTransformer=e,this.tokens=s,this.isImportsTransformEnabled=r\##
}process(){if(this.rootTransformer.processPossibleArrowParamEnd()||this.rootTransformer.processPossibleAsyncArrowWit\##
hTypeParams()||this.rootTransformer.processPossibleTypeRange())return!0;if(this.tokens.matches1(t._public)||this.tok\##
ens.matches1(t._protected)||this.tokens.matches1(t._private)||this.tokens.matches1(t._abstract)||this.tokens.matches\##
1(t._readonly)||this.tokens.matches1(t._override)||this.tokens.matches1(t.nonNullAssertion))return this.tokens.remov\##
eInitialToken(),!0;if(this.tokens.matches1(t._enum)||this.tokens.matches2(t._const,t._enum))return this.processEnum(\##
),!0;if(this.tokens.matches2(t._export,t._enum)||this.tokens.matches3(t._export,t._const,t._enum))return this.proces\##
sEnum(!0),!0;return!1}processEnum(e=!1){this.tokens.removeInitialToken();while(this.tokens.matches1(t._const)||this.\##
tokens.matches1(t._enum))this.tokens.removeToken();let s=this.tokens.identifierName();if(this.tokens.removeToken(),e\##
&&!this.isImportsTransformEnabled)this.tokens.appendCode("export ");if(this.tokens.appendCode(`var ${s}; (function (\##
${s})`),this.tokens.copyExpectedToken(t.braceL),this.processEnumBody(s),this.tokens.copyExpectedToken(t.braceR),e&&t\##
his.isImportsTransformEnabled)this.tokens.appendCode(`)(${s} || (exports.${s} = ${s} = {}));`);else this.tokens.appe\##
ndCode(`)(${s} || (${s} = {}));`)}processEnumBody(e){let s=null;while(!0){if(this.tokens.matches1(t.braceR))break;le\##
t{nameStringCode:r,variableName:o}=this.extractEnumKeyInfo(this.tokens.currentToken());if(this.tokens.removeInitialT\##
oken(),this.tokens.matches3(t.eq,t.string,t.comma)||this.tokens.matches3(t.eq,t.string,t.braceR))this.processStringL\##
iteralEnumMember(e,r,o);else if(this.tokens.matches1(t.eq))this.processExplicitValueEnumMember(e,r,o);else this.proc\##
essImplicitValueEnumMember(e,r,o,s);if(this.tokens.matches1(t.comma))this.tokens.removeToken();if(o!=null)s=o;else s\##
=`${e}[${r}]`}}extractEnumKeyInfo(e){if(e.type===t.name){let s=this.tokens.identifierNameForToken(e);return{nameStri\##
ngCode:`"${s}"`,variableName:ys(s)?s:null}}else if(e.type===t.string){let s=this.tokens.stringValueForToken(e);retur\##
n{nameStringCode:this.tokens.code.slice(e.start,e.end),variableName:ys(s)?s:null}}else throw Error("Expected name or\##
 string at beginning of enum element.")}processStringLiteralEnumMember(e,s,r){if(r!=null)this.tokens.appendCode(`con\##
st ${r}`),this.tokens.copyToken(),this.tokens.copyToken(),this.tokens.appendCode(`; ${e}[${s}] = ${r};`);else this.t\##
okens.appendCode(`${e}[${s}]`),this.tokens.copyToken(),this.tokens.copyToken(),this.tokens.appendCode(";")}processEx\##
plicitValueEnumMember(e,s,r){let o=this.tokens.currentToken().rhsEndIndex;if(o==null)throw Error("Expected rhsEndInd\##
ex on enum assign.");if(r!=null){this.tokens.appendCode(`const ${r}`),this.tokens.copyToken();while(this.tokens.curr\##
entIndex()<o)this.rootTransformer.processToken();this.tokens.appendCode(`; ${e}[${e}[${s}] = ${r}] = ${s};`)}else{th\##
is.tokens.appendCode(`${e}[${e}[${s}]`),this.tokens.copyToken();while(this.tokens.currentIndex()<o)this.rootTransfor\##
mer.processToken();this.tokens.appendCode(`] = ${s};`)}}processImplicitValueEnumMember(e,s,r,o){let a=o!=null?`${o} \##
+ 1`:"0";if(r!=null)this.tokens.appendCode(`const ${r} = ${a}; `),a=r;this.tokens.appendCode(`${e}[${e}[${s}] = ${a}\##
] = ${s};`)}}class pt{__init(){this.transformers=[]}__init2(){this.generatedVariables=[]}constructor(e,s,r,o){pt.pro\##
totype.__init.call(this),pt.prototype.__init2.call(this),this.nameManager=e.nameManager,this.helperManager=e.helperM\##
anager;let{tokenProcessor:a,importProcessor:u}=e;if(this.tokens=a,this.isImportsTransformEnabled=s.includes("imports\##
"),this.isReactHotLoaderTransformEnabled=s.includes("react-hot-loader"),this.disableESTransforms=Boolean(o.disableES\##
Transforms),!o.disableESTransforms)this.transformers.push(new _s(a,this.nameManager)),this.transformers.push(new xs(\##
a)),this.transformers.push(new gs(a,this.nameManager));if(s.includes("jsx")){if(o.jsxRuntime!=="preserve")this.trans\##
formers.push(new Ie(this,a,u,this.nameManager,o));this.transformers.push(new Is(this,a,u,o))}let m=null;if(s.include\##
s("react-hot-loader")){if(!o.filePath)throw Error("filePath is required when using the react-hot-loader transform.")\##
;m=new Ot(a,o.filePath),this.transformers.push(m)}if(s.includes("imports")){if(u===null)throw Error("Expected non-nu\##
ll importProcessor with imports transform enabled.");this.transformers.push(new Me(this,a,u,this.nameManager,this.he\##
lperManager,m,r,Boolean(o.enableLegacyTypeScriptModuleInterop),s.includes("typescript"),s.includes("flow"),Boolean(o\##
.preserveDynamicImport),Boolean(o.keepUnusedImports)))}else this.transformers.push(new ms(a,this.nameManager,this.he\##
lperManager,m,s.includes("typescript"),s.includes("flow"),Boolean(o.keepUnusedImports),o));if(s.includes("flow"))thi\##
s.transformers.push(new ds(this,a,s.includes("imports")));if(s.includes("typescript"))this.transformers.push(new Ts(\##
this,a,s.includes("imports")));if(s.includes("jest"))this.transformers.push(new Ft(this,a,this.nameManager,u))}trans\##
form(){this.tokens.reset(),this.processBalancedCode();let s=this.isImportsTransformEnabled?'"use strict";':"";for(le\##
t u of this.transformers)s+=u.getPrefixCode();s+=this.helperManager.emitHelpers(),s+=this.generatedVariables.map((u)\##
=>` var ${u};`).join("");for(let u of this.transformers)s+=u.getHoistedCode();let r="";for(let u of this.transformer\##
s)r+=u.getSuffixCode();let o=this.tokens.finish(),{code:a}=o;if(a.startsWith("#!")){let u=a.indexOf(`
`);if(u===-1)u=a.length,a+=`
`;return{code:a.slice(0,u+1)+s+a.slice(u+1)+r,mappings:this.shiftMappings(o.mappings,s.length)}}else return{code:s+a\##
+r,mappings:this.shiftMappings(o.mappings,s.length)}}processBalancedCode(){let e=0,s=0;while(!this.tokens.isAtEnd())\##
{if(this.tokens.matches1(t.braceL)||this.tokens.matches1(t.dollarBraceL))e++;else if(this.tokens.matches1(t.braceR))\##
{if(e===0)return;e--}if(this.tokens.matches1(t.parenL))s++;else if(this.tokens.matches1(t.parenR)){if(s===0)return;s\##
--}this.processToken()}}processToken(){if(this.tokens.matches1(t._class)){this.processClass();return}for(let e of th\##
is.transformers)if(e.process())return;this.tokens.copyToken()}processNamedClass(){if(!this.tokens.matches2(t._class,\##
t.name))throw Error("Expected identifier for exported class name.");let e=this.tokens.identifierNameAtIndex(this.tok\##
ens.currentIndex()+1);return this.processClass(),e}processClass(){let e=M1(this,this.tokens,this.nameManager,this.di\##
sableESTransforms),s=(e.headerInfo.isExpression||!e.headerInfo.className)&&e.staticInitializerNames.length+e.instanc\##
eInitializerNames.length>0,r=e.headerInfo.className;if(s)r=this.nameManager.claimFreeName("_class"),this.generatedVa\##
riables.push(r),this.tokens.appendCode(` (${r} =`);let a=this.tokens.currentToken().contextId;if(a==null)throw Error\##
("Expected class to have a context ID.");this.tokens.copyExpectedToken(t._class);while(!this.tokens.matchesContextId\##
AndLabel(t.braceL,a))this.processToken();this.processClassBody(e,r);let u=e.staticInitializerNames.map((m)=>`${r}.${\##
m}()`);if(s)this.tokens.appendCode(`, ${u.map((m)=>`${m}, `).join("")}${r})`);else if(e.staticInitializerNames.lengt\##
h>0)this.tokens.appendCode(` ${u.map((m)=>`${m};`).join(" ")}`)}processClassBody(e,s){let{headerInfo:r,constructorIn\##
sertPos:o,constructorInitializerStatements:a,fields:u,instanceInitializerNames:m,rangesToRemove:x}=e,k=0,T=0,y=this.\##
tokens.currentToken().contextId;if(y==null)throw Error("Expected non-null context ID on class.");if(this.tokens.copy\##
ExpectedToken(t.braceL),this.isReactHotLoaderTransformEnabled)this.tokens.appendCode("__reactstandin__regenerateByEv\##
al(key, code) {this[key] = eval(code);}");let C=a.length+m.length>0;if(o===null&&C){let L=this.makeConstructorInitCo\##
de(a,m,s);if(r.hasSuperclass){let M=this.nameManager.claimFreeName("args");this.tokens.appendCode(`constructor(...${\##
M}) { super(...${M}); ${L}; }`)}else this.tokens.appendCode(`constructor() { ${L}; }`)}while(!this.tokens.matchesCon\##
textIdAndLabel(t.braceR,y))if(k<u.length&&this.tokens.currentIndex()===u[k].start){let L=!1;if(this.tokens.matches1(\##
t.bracketL))this.tokens.copyTokenWithPrefix(`${u[k].initializerName}() {this`);else if(this.tokens.matches1(t.string\##
)||this.tokens.matches1(t.num))this.tokens.copyTokenWithPrefix(`${u[k].initializerName}() {this[`),L=!0;else this.to\##
kens.copyTokenWithPrefix(`${u[k].initializerName}() {this.`);while(this.tokens.currentIndex()<u[k].end){if(L&&this.t\##
okens.currentIndex()===u[k].equalsIndex)this.tokens.appendCode("]");this.processToken()}this.tokens.appendCode("}"),\##
k++}else if(T<x.length&&this.tokens.currentIndex()>=x[T].start){if(this.tokens.currentIndex()<x[T].end)this.tokens.r\##
emoveInitialToken();while(this.tokens.currentIndex()<x[T].end)this.tokens.removeToken();T++}else if(this.tokens.curr\##
entIndex()===o){if(this.tokens.copyToken(),C)this.tokens.appendCode(`;${this.makeConstructorInitCode(a,m,s)};`);this\##
.processToken()}else this.processToken();this.tokens.copyExpectedToken(t.braceR)}makeConstructorInitCode(e,s,r){retu\##
rn[...e,...s.map((o)=>`${r}.prototype.${o}.call(this)`)].join(";")}processPossibleArrowParamEnd(){if(this.tokens.mat\##
ches2(t.parenR,t.colon)&&this.tokens.tokenAtRelativeIndex(1).isType){let e=this.tokens.currentIndex()+1;while(this.t\##
okens.tokens[e].isType)e++;if(this.tokens.matches1AtIndex(e,t.arrow)){this.tokens.removeInitialToken();while(this.to\##
kens.currentIndex()<e)this.tokens.removeToken();return this.tokens.replaceTokenTrimmingLeftWhitespace(") =>"),!0}}re\##
turn!1}processPossibleAsyncArrowWithTypeParams(){if(!this.tokens.matchesContextual(c._async)&&!this.tokens.matches1(\##
t._async))return!1;let e=this.tokens.tokenAtRelativeIndex(1);if(e.type!==t.lessThan||!e.isType)return!1;let s=this.t\##
okens.currentIndex()+1;while(this.tokens.tokens[s].isType)s++;if(this.tokens.matches1AtIndex(s,t.parenL)){this.token\##
s.replaceToken("async ("),this.tokens.removeInitialToken();while(this.tokens.currentIndex()<s)this.tokens.removeToke\##
n();return this.tokens.removeToken(),this.processBalancedCode(),this.processToken(),!0}return!1}processPossibleTypeR\##
ange(){if(this.tokens.currentToken().isType){this.tokens.removeInitialToken();while(this.tokens.currentToken().isTyp\##
e)this.tokens.removeToken();return!0}return!1}shiftMappings(e,s){for(let r=0;r<e.length;r++){let o=e[r];if(o!==void \##
0)e[r]=o+s}return e}}var Vl=$1(ni());function B1(e){let s=new Set;for(let r=0;r<e.tokens.length;r++)if(e.matches1AtI\##
ndex(r,t._import)&&!e.matches3AtIndex(r,t._import,t.name,t.eq))Gl(e,r,s);return s}function Gl(e,s,r){if(s++,e.matche\##
s1AtIndex(s,t.parenL))return;if(e.matches1AtIndex(s,t.name)){if(r.add(e.identifierNameAtIndex(s)),s++,e.matches1AtIn\##
dex(s,t.comma))s++}if(e.matches1AtIndex(s,t.star))s+=2,r.add(e.identifierNameAtIndex(s)),s++;if(e.matches1AtIndex(s,\##
t.braceL))s++,Xl(e,s,r)}function Xl(e,s,r){while(!0){if(e.matches1AtIndex(s,t.braceR))return;let o=ke(e,s);if(s=o.en\##
dIndex,!o.isType)r.add(o.rightName);if(e.matches2AtIndex(s,t.comma,t.braceR))return;else if(e.matches1AtIndex(s,t.br\##
aceR))return;else if(e.matches1AtIndex(s,t.comma))s++;else throw Error(`Unexpected token: ${JSON.stringify(e.tokens[\##
s])}`)}}function ri(e,s){Ir(s);try{let r=Jl(e,s),a=new pt(r,s.transforms,Boolean(s.enableLegacyBabel5ModuleInterop),\##
s).transform(),u={code:a.code};if(s.sourceMapOptions){if(!s.filePath)throw Error("filePath must be specified when ge\##
nerating a source map.");u={...u,sourceMap:Qn(a,s.filePath,s.sourceMapOptions,e,r.tokenProcessor.tokens)}}return u}c\##
atch(r){if(s.filePath)r.message=`Error transforming ${s.filePath}: ${r.message}`;throw r}}function Jl(e,s){let r=s.t\##
ransforms.includes("jsx"),o=s.transforms.includes("typescript"),a=s.transforms.includes("flow"),u=s.disableESTransfo\##
rms===!0,m=Zo(e,r,o,a),{tokens:x,scopes:k}=m,T=new gt(e,x),y=new xt(T),C=new Oe(e,x,a,u,y),L=Boolean(s.enableLegacyT\##
ypeScriptModuleInterop),M=null;if(s.transforms.includes("imports")){if(M=new ye(T,C,L,s,s.transforms.includes("types\##
cript"),Boolean(s.keepUnusedImports),y),M.preprocessTokens(),Gt(C,k,M.getGlobalNames()),s.transforms.includes("types\##
cript")&&!s.keepUnusedImports)M.pruneTypeOnlyImports()}else if(s.transforms.includes("typescript")&&!s.keepUnusedImp\##
orts)Gt(C,k,B1(C));return{tokenProcessor:C,scopes:k,nameManager:T,importProcessor:M,helperManager:y}}globalThis.stri\##
p=(e,s)=>ri(e,{transforms:["typescript","imports"],filePath:s,production:!0,disableESTransforms:!0}).code;})();
"""##
}
