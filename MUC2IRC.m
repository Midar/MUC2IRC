#import <ObjFW/ObjFW.h>

#import "IRCConnection.h"

@interface MUC2IRC: OFObject <OFApplicationDelegate, OFTCPSocketDelegate>
{
	OFTCPSocket *_listeningSocket;
}
@end

OF_APPLICATION_DELEGATE(MUC2IRC)

@implementation MUC2IRC
- (void)applicationDidFinishLaunching
{
	_listeningSocket = [[OFTCPSocket alloc] init];
	[_listeningSocket setDelegate: self];
	[_listeningSocket bindToHost: @"::"
				port: 6667];
	[_listeningSocket listen];
	[_listeningSocket asyncAccept];
}

-    (bool)socket: (OF_KINDOF(OFTCPSocket *))listeningSocket
  didAcceptSocket: (OF_KINDOF(OFTCPSocket *))sock
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
