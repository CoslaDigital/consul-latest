// This function will initialize the sortable lists
var initializeSortable = function() {
  
  // Find all lists with our data-controller="reorder" attribute
  $('ul[data-controller="reorder"]').each(function() {
    var $list = $(this);
    
    // Check if it's already been initialized
    if ($list.data('sortable-initialized')) {
      return;
    }

    var reorderUrl = $list.data('reorder-url');
    var csrfToken = $('meta[name="csrf-token"]').attr('content');

    $list.sortable({
      // 1. The element to click and drag
      handle: '.drag-handle',
      
      // 2. The items inside the list to be sorted
      items: 'li[data-reorder-target="item"]',
      
      // 3. A class for the placeholder element
      placeholder: 'sortable-placeholder',
      
      // 4. This function is called when the user drops an item
      update: function(event, ui) {
        // Get the new order of IDs from the 'data-id' attribute
        var investment_ids = $list.sortable('toArray', { attribute: 'data-id' });

        // Build the data to send to the controller
        var data = {
          _method: 'patch',
          investment_ids: investment_ids,
          authenticity_token: csrfToken // Send CSRF token
        };

        // Send the AJAX request to your Rails controller
        $.ajax({
          url: reorderUrl,
          type: 'POST', // Use POST, _method: 'patch' handles the routing
          data: data,
          success: function() {
            // Re-number the preferences on the screen
            updatePreferenceNumbers($list);
          },
          error: function() {
            alert("There was an error reordering. Please refresh the page.");
            // Revert the list to its original state
            $list.sortable('cancel');
          }
        });
      }
    });

    // Mark as initialized to prevent double-binding
    $list.data('sortable-initialized', true);
  });

  // Helper function to update the "(Preference X)" text
  var updatePreferenceNumbers = function($list) {
    // Find all items within this specific list
    $list.find('li[data-reorder-target="item"]').each(function(index) {
      var $item = $(this);
      var $prefElement = $item.find('.preference-order');
      
      if ($prefElement.length > 0) {
        // Read the translation ("Preference") from the data-attribute
        var prefText = $prefElement.data('pref-text') || 'Preference';
        // Update the text to the new position
        $prefElement.text('(' + prefText + ' ' + (index + 1) + ')');
      }
    });
  };
};

// This ensures the code runs on initial page load
$(document).ready(initializeSortable);

// This ensures it also runs if you use Turbolinks
$(document).on('turbolinks:load', initializeSortable);