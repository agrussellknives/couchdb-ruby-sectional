function(head,req){
	var keys = [];
	while(row=getRow()){
		keys.push(row.id);
	}
	send(toJSON(keys));
}