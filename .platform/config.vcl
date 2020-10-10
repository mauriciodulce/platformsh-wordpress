sub vcl_recv {
    set req.backend_hint = application.backend();
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

    # Remove the proxy header (see https://httpoxy.org/#mitigate-varnish)
    unset req.http.proxy;

    
    if (req.method == "PURGE") {
        return (purge);
    }

    if (req.method == "XCGFULLBAN") {
        ban("req.http.host ~ .*");
        return (synth(200, "Full cache cleared"));
    }

    if (req.http.X-Requested-With == "XMLHttpRequest") {
        return(pass);
    }

    if (req.http.Authorization || req.method == "POST") {
        return (pass);
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    if (req.url ~ "(wp-admin|post\.php|edit\.php|wp-login|wp-json)") {
        return(pass);
    }

    if (req.url ~ "/wp-cron.php" || req.url ~ "preview=true") {
        return (pass);
    }

    if ((req.http.host ~ "my_domain.com" && req.url ~ "^some_specific_filename\.(css|js)")) {
        return (pass);
    }

    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");
    
    # Remove the wp-settings-1 cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-1=[^;]+(; )?", "");

    # Remove the wp-settings-time-1 cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-time-1=[^;]+(; )?", "");

    # Remove the wp test cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "wordpress_test_cookie=[^;]+(; )?", "");

    # Remove the PHPSESSID in members area cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "PHPSESSID=[^;]+(; )?", "");

    unset req.http.Cookie;  

    # Only deal with "normal" types
    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "PATCH" &&
        req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

}

sub vcl_purge {
    set req.method = "GET";
    set req.http.X-Purger = "Purged";

    #return (synth(200, "Purged"));
    return (restart);
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    # 
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

    set beresp.grace = 12h;
    set beresp.ttl = 12h;
}

// sub vcl_deliver {
//     # Happens when we have all the pieces we need, and are about to send the
//     # response to the client.
//     #
//     # You can do accounting or modifying the final object here.
// }

# The routine when we deliver the HTTP request to the user
# Last chance to modify headers that are sent to the client
sub vcl_deliver {
  # Called before a cached object is delivered to the client.

  if (obj.hits > 0) { # Add debug header to see if it's a HIT/MISS and the number of hits, disable when not needed
    set resp.http.X-Cache = "HIT";
  } else {
    set resp.http.X-Cache = "MISS";
  }

  # Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
  # and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
  # So take hits with a grain of salt
  set resp.http.X-Cache-Hits = obj.hits;


  # Remove ban lurker headers
  unset resp.http.X-Host;
  unset resp.http.X-URL;


  # Remove some headers: PHP version
  unset resp.http.X-Powered-By;

  # Remove some headers: Apache version & OS
  unset resp.http.Server;
  unset resp.http.X-Drupal-Cache;
  unset resp.http.X-Varnish;
  unset resp.http.Via;
  unset resp.http.Link;
  unset resp.http.X-Generator;
  unset resp.http.X-Clacks-Overhead;

  return (deliver);
}
sub vcl_synth {
  if (resp.status == 720) {
    # We use this special error status 720 to force redirects with 301 (permanent) redirects
    # To use this, call the following from anywhere in vcl_recv: return (synth(720, "http://host/new.html"));
    set resp.http.Location = resp.reason;
    set resp.status = 301;
    return (deliver);
  } elseif (resp.status == 721) {
    # And we use error status 721 to force redirects with a 302 (temporary) redirect
    # To use this, call the following from anywhere in vcl_recv: return (synth(720, "http://host/new.html"));
    set resp.http.Location = resp.reason;
    set resp.status = 302;
    return (deliver);
  }

  return (deliver);
}


sub vcl_purge {
  # Only handle actual PURGE HTTP methods, everything else is discarded
  if (req.method != "PURGE") {
    # restart request
    set req.http.X-Purge = "Yes";
    return (restart);
  }
}
