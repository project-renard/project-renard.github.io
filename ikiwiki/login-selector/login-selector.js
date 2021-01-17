/*
Based on the Simple OpenID Plugin
http://code.google.com/p/openid-selector/

This code is licenced under the New BSD License.
*/

var selections_email_large = {
    email: {
        name: 'Email',
	icon: 'wikiicons/email.png',
        label: 'Enter your email address:',
        url: null
    }
};
var selections_openid_large = {
    openid: {
        name: 'OpenID',
	icon: 'wikiicons/openidlogin-bg.gif',
        label: 'Enter your OpenID:',
        url: null
    }
};
var selections = $.extend({}, selections_email_large, selections_openid_large);

var selector = {

	ajaxHandler: null,
	cookie_expires: 6*30,	// 6 months.
	cookie_name: 'openid_selection', // historical name
	cookie_path: '/',
	
	img_path: 'images/',
	
	input_id: null,
	selection_url: null,
	selection_id: null,
	othersignin_id: null,
	
    init: function(input_id, login_methods, othersignin_id, othersignin_label) {
        
        var selector_btns = $('#login_btns');
        
        this.input_id = input_id;
        
        $('#login_choice').show();
        $('#login_input_area').empty();
        
        // add box for each selection
	if (login_methods['openid']) {
	        for (id in selections_openid_large) {
			selector_btns.append(this.getBoxHTML(selections_openid_large[id], 'large'));
		}
	}
	if (login_methods['email']) {
		for (id in selections_email_large) {
			selector_btns.prepend(this.getBoxHTML(selections_email_large[id], 'large'));
		}
	}

	if (othersignin_label != "") {
		this.othersignin_label=othersignin_label;
	}
	else {
		this.othersignin_label="other";
	}
	if (othersignin_id != "") {
		this.othersignin_id=othersignin_id;
           	selector_btns.prepend(
        		'<a href="javascript: selector.signin(\'othersignin\');"' +
        		' style="background: #FFF" ' +
        		'class="othersignin login_large_btn">' +
			'<img alt="" width="16" height="16" src="favicon.ico" />' +
			' ' + this.othersignin_label +
			'</a>'
		);
		$('#'+this.othersignin_id).hide();
	}

        $('#login_selector_form').submit(this.submit);
        
        var box_id = this.readCookie();
        if (box_id) {
        	this.signin(box_id, true);
        }
    },
    getBoxHTML: function(selection, box_size) {
	var label="";
	var title=""
	if (box_size == 'large') {
		label=' ' + selection["name"];
	}
	else {
		title=' title="'+selection["name"]+'"';
	}
        var box_id = selection["name"].toLowerCase();
        return '<a' + title +' href="javascript: selector.signin(\''+ box_id +'\');"' +
        		' style="background: #FFF" ' + 
        		'class="' + box_id + ' login_' + box_size + '_btn">' +
			'<img alt="" width="16" height="16" src="' + selection["icon"] + '" />' +
			label +
			'</a>';
    
    },
    /* selection image click */
    signin: function(box_id, onload) {

	if (box_id == 'othersignin') {
	    	this.highlight(box_id);
		$('#login_input_area').empty();
		$('#'+this.othersignin_id).show();
		this.setCookie(box_id);
		return;
	}
	else {
		if (this.othersignin_id) {
			$('#'+this.othersignin_id).hide();
		}
	}

    	var selection = selections[box_id];
  		if (! selection) {
  			return;
  		}
		
		this.highlight(box_id);
		
		this.selection_id = box_id;
		this.selection_url = selection['url'];
		
		// prompt user for input?
		if (selection['label']) {
			this.setCookie(box_id);
			this.useInputBox(selection);
		} else {
			this.setCookie('');
			$('#login_input_area').empty();
			if (! onload) {
				$('#login_selector_form').submit();
			}
		}
    },
    /* Sign-in button click */
    submit: function() {
    	var url = selector.selection_url; 
    	if (url) {
    		url = url.replace('{username}', $('#entry').val());
    		selector.setOpenIdUrl(url);
    	}
	else {
    		selector.setOpenIdUrl("");
	}
    	if (selector.ajaxHandler) {
    		selector.ajaxHandler(selector.selection_id, document.getElementById(selector.input_id).value);
    		return false;
    	}
    	return true;
    },
    setOpenIdUrl: function (url) {
    
	var hidden = $('#'+this.input_id);
	if (hidden.length > 0) {
		hidden.value = url;
    	} else {
		$('#login_selector_form').append('<input style="display:none" id="' + this.input_id + '" name="' + this.input_id + '" value="'+url+'"/>');
    	}
    },
    highlight: function (box_id) {
    	
    	// remove previous highlight.
    	var highlight = $('#login_highlight');
    	if (highlight) {
    		highlight.replaceWith($('#login_highlight a')[0]);
    	}
    	// add new highlight.
    	$('.'+box_id).wrap('<div id="login_highlight"></div>');
    },
    setCookie: function (value) {
    
		var date = new Date();
		date.setTime(date.getTime()+(this.cookie_expires*24*60*60*1000));
		var expires = "; expires="+date.toGMTString();
		
		document.cookie = this.cookie_name+"="+value+expires+"; path=" + this.cookie_path;
    },
    readCookie: function () {
		var nameEQ = this.cookie_name + "=";
		var ca = document.cookie.split(';');
		for(var i=0;i < ca.length;i++) {
			var c = ca[i];
			while (c.charAt(0)==' ') c = c.substring(1,c.length);
			if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
		}
		return null;
    },
    useInputBox: function (selection) {
   	
		var input_area = $('#login_input_area');
		
		var html = '';
		var id = selection['name']+'_entry';
		var value = '';
		var label = selection['label'];
		var style = '';
		
		if (selection['name'] == 'OpenID') {
			id = this.input_id;
			value = '';
			style = 'background:#FFF url(wikiicons/openidlogin-bg.gif) no-repeat scroll 0 50%; padding-left:18px;';
		}
		if (label) {
			html = '<label for="'+ id +'" class="block">' + label + '</label>';
		}
		html += '<input id="'+id+'" type="text" style="'+style+'" name="'+id+'" value="'+value+'" />' + 
					'<input id="selector_submit" type="submit" value="Login"/>';
		
		input_area.empty();
		input_area.append(html);

		$('#'+id).focus();
    },
    setAjaxHandler: function (ajaxFunction) {
    	this.ajaxHandler = ajaxFunction;
    }
};
