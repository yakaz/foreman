//on load
$(function() {
  //select the first tab
  $('.smart-var-tabs li a span').hide();
  select_first_tab();
  //make the remove variable button visible only on the active pill
  $('.smart-var-tabs li a').on('click',function(){ show_delete_button(this);});
  //remove variable click event
  $('.smart-var-tabs li a span').on('click',function(){ remove_node(this);});
})

function select_first_tab(){
  if ($('.smart-var-tabs li').size() > 1){
    $('.tab-content .fields').first().addClass('active');
    $('.smart-var-tabs li').first().addClass('active');
  }
  $('.smart-var-tabs li.active a span').show('highlight',5  );
}

function show_delete_button(item){
  $('.smart-var-tabs li a span:visible').hide();
  $(item).children("span").show('highlight',5);
  if($(item).hasClass('label-success') && ($('.smart-var-tabs li').size()>1)){
    select_first_tab();
  }
}

function remove_node(item){
  $($(item).parent("a").attr("href")).children('.btn-danger').click();
  var pills = $('.smart-var-tabs li a');
  if (pills.size() > 1){pills.first().click();}
  $('.smart-var-tabs li.active a').click();
}

function add_child_node(item) {
    // Setup
    var assoc   = $(item).attr('data-association');           // Name of child
    var content = $('#' + assoc + '_fields_template').html(); // Fields template

    // Make the context correct by replacing new_<parents> with the generated ID
    // of each of the parent objects
    var context = ($(item).closest('.fields').find('input:first').attr('name') || '').replace(new RegExp('\[[a-z]+\]$'), '');

    // context will be something like this for a brand new form:
    // project[tasks_attributes][new_1255929127459][assignments_attributes][new_1255929128105]
    // or for an edit form:
    // project[tasks_attributes][0][assignments_attributes][1]
    if(context) {
      var parent_names = context.match(/[a-z_]+_attributes/g) || [];
      var parent_ids   = context.match(/(new_)?[0-9]+/g) || [];

      for(var i = 0; i < parent_names.length; i++) {
        if(parent_ids[i]) {
          content = content.replace(
            new RegExp('(_' + parent_names[i] + ')_.+?_', 'g'),
            '$1_' + parent_ids[i] + '_');

          content = content.replace(
            new RegExp('(\\[' + parent_names[i] + '\\])\\[.+?\\]', 'g'),
            '$1[' + parent_ids[i] + ']');
        }
      }
    }

    // Make a unique ID for the new child
    var regexp  = new RegExp('new_' + assoc, 'g');
    var new_id  = new Date().getTime();
    content     = content.replace(regexp, "new_" + new_id);
    var field   = '';
    if (assoc == 'lookup_keys') {
      $('.smart-var-tabs .active, .smart-var-content .active').removeClass('active');
      var pill = "<li class='active'><a onclick='show_delete_button(this);' data-toggle='pill' href='#new_" + new_id + "' id='pill_new_" + new_id + "'>new<span onclick='remove_node(this);' class='label label-important fr'>&times;</span></a></li>"
      $('.smart-var-tabs').prepend(pill);
      field = $('.smart-var-content').prepend($(content).addClass('active'));
      $('.smart-var-tabs li.active a').show('highlight', 500);
    } else {
      field = $(content).insertBefore($(item));
    }
    $(item).closest("form").trigger({type: 'nested:fieldAdded', field: field});
    $('a[rel="popover"]').popover();
    return new_id;
}

function remove_child_node(item) {
  var hidden_field = $(item).prev('input[type=hidden]')[0];
  if(hidden_field) {
    hidden_field.value = '1';
  }

  $(item).closest('.fields').hide();
  if($(item).parent().hasClass('fields')) {
    $('#pill_' + $(item).closest('.fields').attr('id')).empty().remove();
  }
  $(item).closest("form").trigger('nested:fieldRemoved');

  return false;
}

function merge_puppetclass_selected(item, cb) {
  item = $(item);
  var target_div = $('#'+item.attr('data-target'));
  if (!(item.attr('data-new'))) target_div.empty();
  var target = $('select[name="lookup_key[id]"][data-target="'+item.attr('data-target')+'"]');
  target.empty();
  target.attr('disabled', true);
  var puppetclass_id = item.val();
  if (puppetclass_id == '') return false;
  if (target.length == 0) return false;
  $.ajax({
    type:'get',
    url:'/puppetclasses/'+puppetclass_id+'/lookup_keys',
    data:'format=json',
    success:function(response){
      if (target.attr('data-new')) {
        target.append($('<option value="">New</option>'));
      } else {
        target.append($('<option value="">Select one</option>'));
      }
      $.each(response, function(index, record){
        record = record['lookup_key'];
        target.append($('<option></option>').attr('value', record['id']).text(record['key']));
      })
      target.attr('disabled', null);
      merge_smartvar_selected(target, true);
      target.focus();
      if (cb) cb(item, target);
    }
  });
}

function merge_smartvar_selected(item, no_auto_focus) {
  item = $(item);
  var value = item.val();
  var target_div = $('#'+item.attr('data-target'));
  if (item.attr('data-new')) {
    var target = $('input[name="lookup_key[key]"][type=text]');
    if (value) {
      target.attr('disabled', true);
      target.val(item.find(':selected').text());
      target.addClass('fade');
    } else {
      target.attr('disabled', null);
      target.val('');
      target.removeClass('fade');
      if (!no_auto_focus) target.focus();
    }
  } else {
    target_div.empty();
    if (!value) return false;
    $.ajax({
      type:'get',
      url:'/lookup_keys/merge?fields_for='+value,
      success:function(response){
        target_div.html(response);
      }
    });
  }
}

$(function(){
  var h = parseLocationHash();
  var load = function(id,target) {
    id = id.split('$');
    target = $('[data-target="'+target+'"]');
    var puppetclass = target.filter('[name="lookup_key[puppetclass_id]"]');
    var lookup_key  = target.filter('[name="lookup_key[id]"]');
    puppetclass.val(id[0]);
    merge_puppetclass_selected(puppetclass, function() {
      lookup_key.val(id[1]);
      merge_smartvar_selected(lookup_key);
    });
  };
  if (h['id_left'])
    load(h['id_left'], 'content-left');
  if (h['id_right'])
    load(h['id_right'], 'content-right');
});
