window.onload = function () {
	var userAgent = navigator.userAgent.toLowerCase();
	var version = /firefox\/(\d+)/.exec(userAgent);
	if (!version || (version.length === 2 && version[1] > 48)) {
		// Reveal the "expand-all-pkgset" button when not in firefox (where
		// summary tags are not supported)
		document.getElementById("expand-all-pkgsets").style.display='inline';
	}
}
