// Ensure the global App object exists
var App = App || {};

App.Accordion = (function() {
  "use strict";

  var initialize = function() {
    var $trigger = $('.accordion-trigger[aria-controls="individual-panel"]');
    var $panel = $('#individual-panel');

    // Stop if the elements don't exist on this page
    if ($trigger.length === 0 || $panel.length === 0) {
      return;
    }

    // 1. Set initial state on page load
    // (Check if the button is set to expanded)
    var isExpanded = $trigger.attr('aria-expanded') === 'true';
    if (!isExpanded) {
      $panel.attr('hidden', '');
    }

    // 2. Add click event handler
    $trigger.on('click', function() {
      var $this = $(this); // The button that was clicked
      var isHidden = $panel.is('[hidden]');

      if (isHidden) {
        // Open it
        $panel.removeAttr('hidden');
        $this.attr('aria-expanded', 'true');
      } else {
        // Close it
        $panel.attr('hidden', '');
        $this.attr('aria-expanded', 'false');
      }
    });
  };

  // This "exports" the initialize function so application.js can call it
  return {
    initialize: initialize
  };
})();