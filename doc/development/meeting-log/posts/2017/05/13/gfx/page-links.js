var Q = JSON.stringify;

if (argv.length != 3)
	print("usage: mutool run page-links.js document.pdf pageNumber")
else {
	var doc = new Document(argv[1]);
	var page = doc.loadPage(parseInt(argv[2])-1);
	var links = page.getLinks();
	print(Q(links));
}
