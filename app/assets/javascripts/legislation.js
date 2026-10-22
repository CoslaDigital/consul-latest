(function() {
  "use strict";

  window.App = window.App || {};

  App.Legislation = {
    initialize: function() {
      // Hide submit buttons on initial load (if you still have them in the view)
      $("form[id^='new_legislation_answer'], form[id^='edit_legislation_answer']").find("input[type='submit']").hide();
      $("form#draft_version_go_to_version input.button").hide();

      // 1. Answer Radio Buttons
      // Use event delegation (document.on) so it survives AJAX DOM replacements
      $(document).off("change.legislation").on("change.legislation", "form[id^='new_legislation_answer'] input[type=radio], form[id^='edit_legislation_answer'] input[type=radio]", function () {
        var form = $(this).closest("form")[0]; // Get the raw DOM element, not the jQuery object

        // Dispatch the native Rails UJS submit event
        Rails.fire(form, 'submit');
      });

      // 2. Version Dropdown
      $(document).off("change.legislation_version").on("change.legislation_version", "form#draft_version_go_to_version select", function () {
        var form = $(this).closest("form")[0];

        Rails.fire(form, 'submit');
      });
    }
  };
}).call(this);
