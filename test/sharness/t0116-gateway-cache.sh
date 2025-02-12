#!/usr/bin/env bash

test_description="Test HTTP Gateway Cache Control Support"

. lib/test-lib.sh

test_init_ipfs
test_launch_ipfs_daemon_without_network

# Cache control support is based on logical roots (each path segment == one logical root).
# To maximize the test surface, we want to test:
# - /ipfs/ content path
# - /ipns/ content path
# - at least 3 levels
# - separate tests for a directory listing and a file
# - have implicit index.html for a good measure
# /ipns/root1/root2/root3/ (/ipns/root1/root2/root3/index.html)

# Note: we cover important edge case here:
# ROOT3_CID - dir listing (dir-index-html response)
# ROOT4_CID - index.html returned as a root response (dir/), instead of generated dir-index-html
# FILE_CID  - index.html returned directly, as a file

test_expect_success "Add the test directory" '
  mkdir -p root2/root3/root4 &&
  echo "hello" > root2/root3/root4/index.html &&
  ROOT1_CID=$(ipfs add -Qrw --cid-version 1 root2)
  ROOT2_CID=$(ipfs resolve -r /ipfs/$ROOT1_CID/root2 | cut -d "/" -f3)
  ROOT3_CID=$(ipfs resolve -r /ipfs/$ROOT1_CID/root2/root3 | cut -d "/" -f3)
  ROOT4_CID=$(ipfs resolve -r /ipfs/$ROOT1_CID/root2/root3/root4 | cut -d "/" -f3)
  FILE_CID=$(ipfs resolve -r /ipfs/$ROOT1_CID/root2/root3/root4/index.html | cut -d "/" -f3)
'

test_expect_success "Prepare IPNS unixfs content path for testing" '
  TEST_IPNS_ID=$(ipfs key gen --ipns-base=base36 --type=ed25519 cache_test_key | head -n1 | tr -d "\n")
  ipfs name publish --key cache_test_key --allow-offline -Q "/ipfs/$ROOT1_CID" > name_publish_out &&
  test_check_peerid "${TEST_IPNS_ID}" &&
  ipfs name resolve "${TEST_IPNS_ID}" > output &&
  printf "/ipfs/%s\n" "$ROOT1_CID" > expected &&
  test_cmp expected output
'

# GET /ipfs/
    test_expect_success "GET for /ipfs/ unixfs dir listing succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/" >/dev/null 2>curl_ipfs_dir_listing_output &&
    cat curl_ipfs_dir_listing_output
    '
    test_expect_success "GET for /ipfs/ unixfs dir with index.html succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/" >/dev/null 2>curl_ipfs_dir_index.html_output &&
    cat curl_ipfs_dir_index.html_output
    '
    test_expect_success "GET for /ipfs/ unixfs file succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_ipfs_file_output &&
    cat curl_ipfs_file_output
    '
# GET /ipns/
    test_expect_success "GET for /ipns/ unixfs dir listing succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipns/$TEST_IPNS_ID/root2/root3/" >/dev/null 2>curl_ipns_dir_listing_output &&
    cat curl_ipns_dir_listing_output
    '
    test_expect_success "GET for /ipns/ unixfs dir with index.html succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipns/$TEST_IPNS_ID/root2/root3/root4/" >/dev/null 2>curl_ipns_dir_index.html_output &&
    cat curl_ipns_dir_index.html_output
    '
    test_expect_success "GET for /ipns/ unixfs file succeeds" '
    curl -svX GET "http://127.0.0.1:$GWAY_PORT/ipns/$TEST_IPNS_ID/root2/root3/root4/index.html" >/dev/null 2>curl_ipns_file_output &&
    cat curl_ipns_file_output
    '

# Cache-Control: only-if-cached
    test_expect_success "HEAD for /ipfs/ with only-if-cached succeeds when in local datastore" '
    curl -sv -I -H "Cache-Control: only-if-cached" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" > curl_onlyifcached_postitive_head 2>&1 &&
    cat curl_onlyifcached_postitive_head &&
    grep "< HTTP/1.1 200 OK" curl_onlyifcached_postitive_head
    '
    test_expect_success "HEAD for /ipfs/ with only-if-cached fails when not in local datastore" '
    curl -sv -I -H "Cache-Control: only-if-cached" "http://127.0.0.1:$GWAY_PORT/ipfs/$(date | ipfs add --only-hash -Q)" > curl_onlyifcached_negative_head 2>&1 &&
    cat curl_onlyifcached_negative_head &&
    grep "< HTTP/1.1 412 Precondition Failed" curl_onlyifcached_negative_head
    '
    test_expect_success "GET for /ipfs/ with only-if-cached succeeds when in local datastore" '
    curl -svX GET -H "Cache-Control: only-if-cached" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_onlyifcached_postitive_out &&
    cat curl_onlyifcached_postitive_out &&
    grep "< HTTP/1.1 200 OK" curl_onlyifcached_postitive_out
    '
    test_expect_success "GET for /ipfs/ with only-if-cached fails when not in local datastore" '
    curl -svX GET -H "Cache-Control: only-if-cached" "http://127.0.0.1:$GWAY_PORT/ipfs/$(date | ipfs add --only-hash -Q)" >/dev/null 2>curl_onlyifcached_negative_out &&
    cat curl_onlyifcached_negative_out &&
    grep "< HTTP/1.1 412 Precondition Failed" curl_onlyifcached_negative_out
    '

# X-Ipfs-Path

    ## dir generated listing
    test_expect_success "GET /ipfs/ dir listing response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipfs/$ROOT1_CID/root2/root3" curl_ipfs_dir_listing_output
    '
    test_expect_success "GET /ipns/ dir listing response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipns/$TEST_IPNS_ID/root2/root3" curl_ipns_dir_listing_output
    '

    ## dir static index.html
    test_expect_success "GET /ipfs/ dir index.html response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipfs/$ROOT1_CID/root2/root3/root4/" curl_ipfs_dir_index.html_output
    '
    test_expect_success "GET /ipns/ dir index.html response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipns/$TEST_IPNS_ID/root2/root3/root4/" curl_ipns_dir_index.html_output
    '

    # file
    test_expect_success "GET /ipfs/ file response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipfs/$ROOT1_CID/root2/root3/root4/index.html" curl_ipfs_file_output
    '
    test_expect_success "GET /ipns/ file response has original content path in X-Ipfs-Path" '
    grep "< X-Ipfs-Path: /ipns/$TEST_IPNS_ID/root2/root3/root4/index.html" curl_ipns_file_output
    '

# X-Ipfs-Roots

    ## dir generated listing
    test_expect_success "GET /ipfs/ dir listing response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID}" curl_ipfs_dir_listing_output
    '
    test_expect_success "GET /ipns/ dir listing response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID}" curl_ipns_dir_listing_output
    '

    ## dir static index.html
    test_expect_success "GET /ipfs/ dir index.html response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID},${ROOT4_CID}" curl_ipfs_dir_index.html_output
    '
    test_expect_success "GET /ipns/ dir index.html response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID},${ROOT4_CID}" curl_ipns_dir_index.html_output
    '

    ## file
    test_expect_success "GET /ipfs/ file response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID},${ROOT4_CID},${FILE_CID}" curl_ipfs_file_output
    '
    test_expect_success "GET /ipns/ file response has logical CID roots in X-Ipfs-Roots" '
    grep "< X-Ipfs-Roots: ${ROOT1_CID},${ROOT2_CID},${ROOT3_CID},${ROOT4_CID},${FILE_CID}" curl_ipns_file_output
    '

# Etag

    ## dir generated listing
    test_expect_success "GET /ipfs/ dir response has special Etag for generated dir listing" '
    grep -E "< Etag: \"DirIndex-.+_CID-${ROOT3_CID}\"" curl_ipfs_dir_listing_output
    '
    test_expect_success "GET /ipns/ dir response has special Etag for generated dir listing" '
    grep -E "< Etag: \"DirIndex-.+_CID-${ROOT3_CID}\"" curl_ipns_dir_listing_output
    '

    ## dir static index.html should use CID of  the index.html file for improved HTTP caching
    test_expect_success "GET /ipfs/ dir index.html response has dir CID as Etag" '
    grep "< Etag: \"${ROOT4_CID}\"" curl_ipfs_dir_index.html_output
    '
    test_expect_success "GET /ipns/ dir index.html response has dir CID as Etag" '
    grep "< Etag: \"${ROOT4_CID}\"" curl_ipns_dir_index.html_output
    '

    ## file
    test_expect_success "GET /ipfs/ response has CID as Etag for a file" '
    grep "< Etag: \"${FILE_CID}\"" curl_ipfs_file_output
    '
    test_expect_success "GET /ipns/ response has CID as Etag for a file" '
    grep "< Etag: \"${FILE_CID}\"" curl_ipns_file_output
    '

# If-None-Match (return 304 Not Modified when client sends matching Etag they already have)

    test_expect_success "GET for /ipfs/ file with matching Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: \"$FILE_CID\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipfs/ dir with index.html file with matching Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: \"$ROOT4_CID\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipfs/ file with matching third Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: \"fakeEtag1\", \"fakeEtag2\", \"$FILE_CID\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipfs/ file with matching weak Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: W/\"$FILE_CID\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipfs/ file with wildcard Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: *" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/root4/index.html" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipns/ file with matching Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: \"$FILE_CID\"" "http://127.0.0.1:$GWAY_PORT/ipns/$TEST_IPNS_ID/root2/root3/root4/index.html" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    test_expect_success "GET for /ipfs/ dir listing with matching weak Etag in If-None-Match returns 304 Not Modified" '
    curl -svX GET -H "If-None-Match: W/\"$ROOT3_CID\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

    # DirIndex etag is based on xxhash(./assets/dir-index-html), so we need to fetch it dynamically
    test_expect_success "GET for /ipfs/ dir listing with matching strong Etag in If-None-Match returns 304 Not Modified" '
    curl -Is "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/"| grep -i Etag | cut -f2- -d: | tr -d "[:space:]\"" > dir_index_etag &&
    curl -svX GET -H "If-None-Match: \"$(<dir_index_etag)\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '
    test_expect_success "GET for /ipfs/ dir listing with matching weak Etag in If-None-Match returns 304 Not Modified" '
    curl -Is "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/"| grep -i Etag | cut -f2- -d: | tr -d "[:space:]\"" > dir_index_etag &&
    curl -svX GET -H "If-None-Match: W/\"$(<dir_index_etag)\"" "http://127.0.0.1:$GWAY_PORT/ipfs/$ROOT1_CID/root2/root3/" >/dev/null 2>curl_output &&
    test_should_contain "304 Not Modified" curl_output
    '

test_kill_ipfs_daemon

test_done
