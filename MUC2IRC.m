/*
 * Copyright (c) 2018, 2019, 2020 Jonathan Schleifer <js@nil.im>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice is present in all copies.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

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
	[_listeningSocket bindToHost: @"::"
				port: 6667];
	[_listeningSocket listen];
	_listeningSocket.delegate = self;
	[_listeningSocket asyncAccept];
}

-    (bool)socket: (OFTCPSocket *)listeningSocket
  didAcceptSocket: (OFTCPSocket *)sock
	exception: (id)exception;
{
	if (exception != nil) {
		of_log(@"Exception while accepting socket: %@", exception);
		return false;
	}

	of_log(@"Accepted connection from %@",
	    of_socket_address_ip_string(sock.remoteAddress, NULL));

	[IRCConnection connectionWithSocket: sock];

	return true;
}
@end
