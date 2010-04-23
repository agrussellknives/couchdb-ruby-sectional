//simple array.has function
Array.prototype.has=function(v){
for (var i=0; i<this.length; i++){
if (this[i]==v) return i;
}
return false;
};

Object.prototype.keys = function() {
	var keys = [];
	for(var k in this) {
		keys.push(k);
	};
	return keys;
};

Array.prototype.isEqual = function(a) {
	for (var i=0; i < this.length; i++) {
		if(this[i] != a[i]) {
			return false;
		}
	}
	return true;
};

//simple string.format function
String.prototype.format = function() {
var pattern = /\{\d+\}/g;
var args = arguments;
return this.replace(pattern,function(capture) {
	return args[capture.match(/\d+/)]; });
};

Date.prototype.toObject = function() {
var v = ['year','month','day','hour','minute','second','millisecond'];
var rv = {};
for(var i=0;i<v.length;i++) {
	switch(v[i]){
		case 'year': rv.year = this.getFullYear(); break;
		case 'month' : rv.month = this.getMonth(); break;
		case 'day' : rv.day = this.getDay(); break;
		case 'hour' : rv.hour = this.getHours(); break;
		case 'minute' : rv.minute = this.getMinutes(); break;
		case 'second' : rv.second = this.getSeconds(); break;
		case 'millisecond' : rv.millisecond = this.getMilliseconds(); break;
		default: return toString();
	}
}
return rv;
};

Date.prototype.fromObject = function(obj) {
var v =['year','month','day','hour','minute','second','millisecond'];
var today = new Date();
today = today.toObject();
for(var i=0;i<v.length;i++) {
	switch(v[i]){
		case 'year': this.setFullYear(obj.year ? obj.year : today.year); break;
		case 'month': this.setMonth(obj.month ? obj.month : today.month); break;
		case 'day': this.setDate(obj.day ? obj.day : today.day); break;
		case 'hour': this.setHours(obj.hour ? obj.hour : today.hour); break;
		case 'minute': this.setMinutes(obj.hour ? obj.minute : today.minute); break;
		case 'second': this.setSeconds(obj.second ? obj.second : today.second); break;
		case 'millisecond': this.setMilliseconds(obj.millisecond ? obj.millisecond : today.millisecond); break;
		default: throw new Error('Date constructor object has a bad member.');
	}
}
return this;
};

