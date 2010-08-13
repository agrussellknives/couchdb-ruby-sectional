function(head,req) {
	var row;
	var compiled_rows = [];
	consolidate_row = function(row) {
		if (typeof consolidate_row.prev === 'undefined') { 
			consolidate_row.prev = row; 
			return false; 
		}
		if (toJSON(row.key) == toJSON(consolidate_row.prev.key)) {
			consolidate_row.prev.value.products.push(row.value.products[0]);
			return false;
		}
		else {
			consolidated = consolidate_row.prev;
			consolidate_row.prev = row;
			return consolidated;
		}
	};
	
	while(row = getRow()) {
		var result = consolidate_row(row);
		if(result) { 
			(function(){
				var obj = {};
				obj.key = result.key;
				obj.value = result.value;
				compiled_rows.push(obj);
			}());
		}
	}
	send(toJSON(compiled_rows));
}