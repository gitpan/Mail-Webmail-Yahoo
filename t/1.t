use Test;

BEGIN { plan tests => 1; }; 

print qq{
Ideally there would be tests here, but since it would be impossible to
test anything beyond very basic functionality, due to having to provide a
username and password, there are no tests beyond 'did the package load ok'.
};


use Mail::Webmail::Yahoo;

ok(1);
