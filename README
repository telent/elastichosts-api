In this repository:

## elastichosts-upload.sh 

This is a lightly-hacked version of the Drive Upload tool that
Elastichosts supply as an example of the API.  It adds a -s flag that
allows upload of shared images, and attempts (not entirely
successfully) to detect when the -z flag is misbehaving.

## eh-upload.rb 

A work-in-progress Ruby drive upload script.  The salient difference
between this and the standard upload tool is in the way it gzips in
transit: elastichosts-upload gzips each chunk and the server
uncompresses and writes it before preparing to receive the next chunk,
but eh-upload.rb compresses the the entire image before sending it (in
chunks) into a temporary drive image on the server, then uses more
Elastichosts API calls to decompress that temporary image in situ.
For images with lots and lots of zero in them, this is expected (by
me, at least) to be faster

### Installation and invocation

Prerequisites: Ruby, Gembundler

$ bundle install
$ bundle exec ruby eh-upload.rb --help

