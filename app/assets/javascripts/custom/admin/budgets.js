(function() {
  "use strict";

  App.AdminBudgetForm = {
    toggleFields: function() {
      var form = $(".budgets-form");
      if (form.length === 0) { return; }

      var allVotingStyles;
      try {
        // Explicitly get the data and parse it as JSON.
        // This is more robust than relying on jQuery's automatic parsing.
        var stylesData = form.data("budget-form-voting-styles-value");
        allVotingStyles = (typeof stylesData === 'string') ? JSON.parse(stylesData) : stylesData;
      } catch (e) {
        console.error("Could not parse voting styles JSON from data attribute:", e, stylesData);
        allVotingStyles = {}; // Default to an empty object on failure to prevent further errors
      }

      var kind = $("#budget_kind").val();
      var stylesForKind = allVotingStyles[kind] || [];
      
      var budgetFields = $("[data-budget-form-target='budgetFields']");
      var electionFields = $("[data-budget-form-target='electionFields']");
      var votingStyleSelect = $("[data-budget-form-target='votingStyleSelect']");
      
      if (kind === "budget") {
        budgetFields.show();
        electionFields.hide();
      } else if (kind === "election") {
        budgetFields.hide();
        electionFields.show();
      }
      
      votingStyleSelect.empty();
      $.each(stylesForKind, function(index, style) {
        votingStyleSelect.append($("<option>").val(style[1]).text(style[0]));
      });
    },

    attachChangeListener: function() {
      $("#budget_kind").on("change", function() {
        App.AdminBudgetForm.toggleFields();
      });
    },

    initialize: function() {
      this.toggleFields();
      this.attachChangeListener();
    }
  };

}).call(this);