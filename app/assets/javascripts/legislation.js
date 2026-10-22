(function() {
  "use strict";

  window.App = window.App || {};

  App.Legislation = {
    initialize: function() {
      // Hide buttons on initial load
      $("form[id^='new_legislation_answer'], form[id^='edit_legislation_answer']").find("input[type='submit']").hide();
      $("form#draft_version_go_to_version input.button").hide();

      $(document).off("change.legislation").on("change.legislation", "form[id^='new_legislation_answer'] input[type=radio], form[id^='edit_legislation_answer'] input[type=radio]", function () {
        var $form = $(this).closest("form");

        // Instead of bypassing Rails UJS with $form.submit(),
        // we simulate a physical click on the hidden submit button
        $form.find("input[type='submit']").trigger('click');
      });

      $(document).off("change.legislation_version").on("change.legislation_version", "form#draft_version_go_to_version select", function () {
        $(this).closest("form").find("input[type='submit']").trigger('click');
      });
    }
  };
}).call(this);
