function(item) {
	if(item.type == 'category'){
		emit(item._id,item);
	}
}