(function () {
  "use strict";

  $(document).on("click", ".copy-link", function (e) {
    e.preventDefault();

    const $link = $(this);
    const url = $link.attr("href");

    navigator.clipboard.writeText(url).then(function () {
      const originalTitle = $link.attr("title");
      $link.attr("title", "Copied!");

      setTimeout(function () {
        $link.attr("title", originalTitle);
      }, 2000);
    }).catch(function () {
      alert("Press Ctrl+C to copy: " + url);
    });
  });
})();
