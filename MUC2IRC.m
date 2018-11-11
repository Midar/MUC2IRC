#import <ObjFW/ObjFW.h>

#import "IRCConnection.h"

@interface MUC2IRC: OFObject <OFApplicationDelegate>
{
	OFTCPSocket *_listeningSocket;
}

-    (bool)socket: (OF_KINDOF(OFTCPSocket *))listeningSocket
  didAcceptSocket: (OF_KINDOF(OFTCPSocket *))sock
	  context: (id)context
	exception: (id)exception;
@end

OF_APPLICATION_DELEGATE(MUC2IRC)

@implementation MUC2IRC
- (void)applicationDidFinishLaunching
{
	_listeningSocket = [[OFTCPSocket alloc] init];
	[_listeningSocket bindToHost: @"::"
				port: 6667];
	[_listeningSocket listen];
	[_listeningSocket asyncAcceptWithTarget: self
				       selector: @selector(socket:
						     didAcceptSocket:context:
						     exception:)
					context: nil];
}

-    (bool)socket: (OF_KINDOF(OFTCPSocket *))listeningSocket
  didAcceptSocket: (OF_KINDOF(OFTCPSocket *))sock
	  context: (id)context
	exception: (id)exception;
{
	if (exception != nil) {
		of_log(@"Exception while accepting socket: %@", exception);
		return false;
	}

	of_log(@"Accepted connection from %@",
	    of_socket_address_ip_string([sock remoteAddress], NULL));

	[IRCConnection connectionWithSocket: sock];

	return true;
}
@end
