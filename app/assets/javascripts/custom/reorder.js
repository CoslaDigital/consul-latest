var initializeSortable = function () {
  $('ul[data-controller="reorder"]').each(function () {
    var $list = $(this);

    // Always destroy and re-init — safe, cheap, and kills stale bindings.
    if ($list.hasClass('ui-sortable')) {
      try {
        $list.sortable('destroy');
      } catch (e) {
      }
    }

    var reorderUrl = $list.data('reorder-url');
    if (!reorderUrl) return;

    var csrfToken = $('meta[name="csrf-token"]').attr('content');

    $list.sortable({
      handle: '.ballot-item__handle, .drag-handle',
      items: 'li[data-reorder-target="item"]',
      placeholder: 'sortable-placeholder',
      update: function (event, ui) {
        var investment_ids = $list.sortable('toArray', {attribute: 'data-id'});
        $.ajax({
          url: reorderUrl,
          type: 'POST',
          data: {
            _method: 'patch',
            investment_ids: investment_ids,
            authenticity_token: csrfToken
          },
          success: function () {
            updatePreferenceNumbers($list);
          },
          error: function () {
            alert("There was an error reordering. Please refresh the page.");
            $list.sortable('cancel');
          }
        });
      }
    });
  });

  var updatePreferenceNumbers = function ($list) {
    $list.find('li[data-reorder-target="item"]').each(function (index) {
      var $prefElement = $(this).find('.preference-order');
      if ($prefElement.length > 0) {
        var prefText = $prefElement.data('pref-text') || 'Preference';
        $prefElement.text('(' + prefText + ' ' + (index + 1) + ')');
      }
    });
  };
};

// Expose globally so inline .js.erb responses and the devtools console can reach it.
// This is essential if this file is loaded as an ES module (where top-level `var`
// is module-scoped, not attached to `window`).
window.initializeSortable = initializeSortable;

// Initial page loads
$(document).ready(initializeSortable);
$(document).on('turbolinks:load', initializeSortable);
$(document).on('turbo:load turbo:frame-load', initializeSortable);

// Re-init after every AJAX response, debounced so bursts don't thrash.
// Skip the reorder PATCH itself — it doesn't replace the DOM.
//
// NOTE: `.off(...).on(...)` is deliberate. `document` persists across Turbolinks /
// Turbo navigations, so without `.off()` a stale handler (registered on a previous
// page load, possibly with `undefined` as the callback) would remain attached and
// shadow the real one. This is what was causing the empty anonymous handler.
var sortableTimer;

$(document)
  .off('ajaxSuccess.sortableReinit')
  .on('ajaxSuccess.sortableReinit', function (event, xhr, settings) {
    if (settings.url && settings.url.indexOf('/ballot/reorder') !== -1) return;

    clearTimeout(sortableTimer);
    sortableTimer = setTimeout(window.initializeSortable, 50);
  });
