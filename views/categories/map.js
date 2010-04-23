function(item) {// we create a copy of the item to operate on.
	// !code lib/jquery/core.js
	
	var holder = {};
	var keycodes = item['keycodes'];
	var presentations = item['presentations'];
	
	// copy item into the holder array
	$.extend(true,holder,item);
	
	// remove the keys from the temporary item
	delete holder['keycodes'];
	delete holder['presentations'];

	var p_list = {};
	
	var section = holder['type']+'s';

	fill_presentations = function(code,presentation_list,type) {
		for(var key in presentation_list) {
			presentation = presentation_list[key];
				if(presentation.type == 'category') {
					for(var override_key in presentation) {
						if(override_key != 'type') {
							holder[override_key] = presentation[override_key];
						}
					}
					var value = {};
					var temp = {};
					value[section] = [];
					value[section].push(holder);
					emit([key,code],value);
				}
			}
		};
	
	fill_presentations('DEFAULT',item.presentations);
	
	// okay, just ignore erros for now.
	try{
		$.each(keycodes,function(v){
			fill_presentations(v.code,v.presentations);
		});
	}
	catch(err){;}
}