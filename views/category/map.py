def fun(item): 
    
    holder = {}
    keycodes = item['keycodes']
    
    master_item = item.copy()
    
    del master_item['keycodes']
    del master_item['presentations']
    
    holder = master_item.copy()

    keycodes = item['keycodes']
    # move any presentation not under a "keycode" into the "DEFAULT" keycode
    keycodes['DEFAULT'] = item['presentations']
    del item['presentations']
    
    for keycode in item['keycodes']:
        for presentation in keycode['presentations'].keys():
            # restore original item settings for each presentation
            holder = master_item.copy()
            if presentation['type'] == 'category':
                for attribute in presentation.keys():
                    if attribute <> 'type':
                        holder[attribute] = presentation[attribute]
                yield [presentation.key, keycode], [holder[x] for x in holder.keys()]