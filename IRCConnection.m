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

#include <assert.h>
#include <stdarg.h>

#import "IRCConnection.h"
#import "config.h"

@interface IRCConnection () <OFTCPSocketDelegate, XMPPConnectionDelegate>
- (void)processLine: (OFString *)line;
- (void)sendLine: (OFConstantString *)format, ...;
- (void)sendStatus: (unsigned short)status
	 arguments: (OFArray OF_GENERIC(OFString *) *)arguments;
- (void)checkHelloComplete;
- (void)sendPresenceForChannel: (OFString *)channel
			  type: (OFString *)type;
- (void)joinChannel: (OFString *)channel;
- (void)leaveChannel: (OFString *)channel;
@end

static OFString *
messageForStatus(unsigned short status)
{
	switch (status) {
	case 366:
		return @"End of /NAMES list";
	case 401:
		return @"No such nick/channel";
	case 403:
		return @"No such channel";
	case 405:
		return @"You have joined too many channels";
	case 411:
		return @"No recipient given";
	case 412:
		return @"No text to send";
	case 421:
		return @"Unknown command";
	case 431:
		return @"No nickname given";
	case 461:
		return @"Not enough parameters";
	default:
		return nil;
	}
}

@implementation IRCConnection
@synthesize nickname = _nickname, username = _username, realname = _realname;

+ (instancetype)connectionWithSocket: (OFTCPSocket *)sock
{
	return [[[self alloc] initWithSocket: sock] autorelease];
}

- (instancetype)initWithSocket: (OFTCPSocket *)sock
{
	self = [super init];

	@try {
		_socket = [sock retain];
		_socket.delegate = self;

		_XMPPConnection = [[XMPPConnection alloc] init];
		_XMPPConnection.domain = XMPP_HOST;
		_XMPPConnection.resource = XMPP_RESOURCE;
		_XMPPConnection.usesAnonymousAuthentication = true;
		[_XMPPConnection addDelegate: self];
		[_XMPPConnection asyncConnect];

		_nicknamesInChannel = [[OFMutableSet alloc] init];

		/*
		 * Need to keep ourselves alive until the XMPP connection is
		 * closed.
		 */
		[self retain];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_socket release];
	[_XMPPConnection release];
	[_joinedChannel release];
	[_nicknamesInChannel release];

	[super dealloc];
}

-  (void)connection: (XMPPConnection *)connection
  didReceiveElement: (OFXMLElement *)element
{
	of_log(@"[XMPP for %@] > %@",
	    of_socket_address_ip_string([_socket remoteAddress], NULL),
	    element);
}

- (void)connection: (XMPPConnection *)connection
    didSendElement: (OFXMLElement *)element
{
	of_log(@"[XMPP for %@] < %@",
	    of_socket_address_ip_string([_socket remoteAddress], NULL),
	    element);
}

- (void)connectionWasClosed: (XMPPConnection *)connection
{
	of_log(@"XMPP connection for %@ was closed",
	    of_socket_address_ip_string(_socket.remoteAddress, NULL));

	[self release];
}

- (void)connection: (XMPPConnection *)connection
     wasBoundToJID: (XMPPJID *)JID
{
	of_log(@"XMPP connection for %@ has JID %@",
	    of_socket_address_ip_string(_socket.remoteAddress, NULL), JID);

	[_socket asyncReadLine];
}

-   (void)connection: (XMPPConnection *)connection
  didReceivePresence: (XMPPPresence *)presence
{
	XMPPJID *from = presence.from;
	OFString *fromNode = from.node;
	OFString *fromResource = from.resource;
	OFString *presenceType = presence.type;

	/* We only care about MUC presences */
	if (![from.domain isEqual: MUC_HOST] || fromResource == nil)
		return;

	if (_joinedChannel != nil && [presenceType isEqual: @"unavailable"]) {
		[_nicknamesInChannel removeObject: fromResource];

		if ([fromResource isEqual: _nickname]) {
			[_joinedChannel release];
			_joinedChannel = nil;

			[_nicknamesInChannel removeAllObjects];
		}

		[self sendLine: @":%@!%@@%@ PART #%@",
				fromResource, fromNode, from.domain, fromNode];
	} else if (presenceType == nil) {
		bool sendList = false;

		if ([fromResource isEqual: _nickname]) {
			assert(_joinedChannel == nil);

			_joinedChannel = [fromNode copy];
			sendList = true;
		}

		[_nicknamesInChannel addObject: fromResource];

		[self sendLine: @":%@!%@@%@ JOIN #%@",
				fromResource, fromNode, from.domain, fromNode];

		if (sendList) {
			OFString *channel = [fromNode
			    stringByPrependingString: @"#"];
			OFArray *arguments = [OFArray arrayWithObject: channel];

			for (OFString *nickname in _nicknamesInChannel)
				[self sendLine:
				    @":" IRC_HOST " 353 %@ = %@ :%@",
				    _nickname, channel, nickname];

			[self sendStatus: 366
			       arguments: arguments];
		}
	}
}

-  (void)connection: (XMPPConnection *)connection
  didReceiveMessage: (XMPPMessage *)message
{
	XMPPJID *from = message.from;
	OFString *fromNode = from.node;
	OFString *fromResource = from.resource;
	OFString *body = message.body;

	/*
	 * We only care about MUC messages from the room we joined that are not
	 * self-messages.
	 */
	if (![from.domain isEqual: MUC_HOST] ||
	    ![fromNode isEqual: _joinedChannel] ||
	    [fromResource isEqual: _nickname] ||
	    ![message.type isEqual: @"groupchat"])
		return;

	for (OFString *line in [body componentsSeparatedByString: @"\n"])
		[self sendLine: @":%@!%@@%@ PRIVMSG #%@ :%@",
				fromResource, fromNode, from.domain, fromNode,
				line];
}

-  (void)connection: (XMPPConnection *)connection
  didThrowException: (id)exception
{
	of_log(@"XMPP connection for %@ threw exception: %@",
	    of_socket_address_ip_string(_socket.remoteAddress, NULL),
	    exception);
}

- (bool)stream: (OFStream *)stream
   didReadLine: (OFString *)line
     exception: (id)exception
{
	OFTCPSocket *sock = (OFTCPSocket *)stream;

	if (exception != nil) {
		of_log(@"Exception in connection from %@",
		    of_socket_address_ip_string(sock.remoteAddress, NULL));
		return false;
	}

	if (line == nil) {
		of_log(@"Connection from %@ closed",
		    of_socket_address_ip_string(sock.remoteAddress, NULL));

		[_XMPPConnection close];
		return false;
	}

	[self processLine: line];

	return true;
}

- (void)processLine: (OFString *)line
{
	OFArray OF_GENERIC(OFString *) *components =
	    [line componentsSeparatedByString: @" "];
	OFString *action = [[components objectAtIndex: 0] uppercaseString];

	of_log(@"[%@] > %@",
	    of_socket_address_ip_string(_socket.remoteAddress, NULL), line);

	if ([action isEqual: @"NICK"]) {
		OFString *nickname;

		if (components.count < 2) {
			[self sendStatus: 431
			       arguments: nil];
			return;
		}

		nickname = [components objectAtIndex: 1];
		if ([nickname hasPrefix: @":"])
			nickname = [nickname substringWithRange:
			    of_range(1, nickname.length - 1)];

		if ([nickname length] == 0) {
			[self sendStatus: 431
			       arguments: nil];
			return;
		}

		self.nickname = nickname;
		[self checkHelloComplete];
	} else if ([action isEqual: @"USER"]) {
		OFString *username;
		OFString *hostname;
		OFString *servername;
		OFString *realname;

		if (components.count < 5) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"USER"]];
			return;
		}

		username = [components objectAtIndex: 1];
		hostname = [components objectAtIndex: 2];
		servername = [components objectAtIndex: 3];
		realname = [components objectAtIndex: 4];

		if ([realname hasPrefix: @":"])
			realname = [realname substringWithRange:
			    of_range(1, realname.length - 1)];

		if ([realname length] == 0) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"USER"]];
			return;
		}

		self.username = username;
		self.realname = realname;
		[self checkHelloComplete];
	} else if ([action isEqual: @"JOIN"]) {
		if ([components count] < 2) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"JOIN"]];
			return;
		}

		if (_joinedChannel != nil) {
			[self sendStatus: 405
			       arguments: [components objectsInRange:
					      of_range(1, 1)]];
			[self sendLine:
			    @":" IRC_HOST @" NOTICE %@ :You can only join one "
			    @"channel per connection.", _nickname];
			[self sendLine:
			    @":" IRC_HOST @" NOTICE %@ :Please create a new "
			    @"connection to join another channel.", _nickname];
			[self sendLine:
			    @":" IRC_HOST @" NOTICE %@ :This is necessary as "
			    @"different MUCs can have different users with the "
			    @"same nickname.", _nickname];
			return;
		}

		[self joinChannel: [components objectAtIndex: 1]];
	} else if ([action isEqual: @"PART"]) {
		if (components.count < 2) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"LEAVE"]];
			return;
		}

		[self leaveChannel: [components objectAtIndex: 1]];
	} else if ([action isEqual: @"PRIVMSG"]) {
		OFString *channel;
		size_t messagePos;
		OFString *message;

		if (components.count < 2) {
			[self sendStatus: 411
			       arguments: nil];
			return;
		}

		if (components.count < 3) {
			[self sendStatus: 412
			       arguments: nil];
			return;
		}

		channel = [components objectAtIndex: 1];

		messagePos = action.length + channel.length + 2;
		message = [line substringWithRange:
		    of_range(messagePos, line.length - messagePos)];

		if ([message hasPrefix: @":"])
			message = [message substringWithRange:
			    of_range(1, message.length - 1)];

		[self sendMessage: message
			toChannel: channel];
	} else
		[self sendStatus: 421
		       arguments: [OFArray arrayWithObject: action]];
}

- (void)sendLine: (OFConstantString *)format, ...
{
	va_list arguments;
	va_start(arguments, format);

	of_log(@"[%@] < %@",
	    of_socket_address_ip_string(_socket.remoteAddress, NULL),
	    [[[OFString alloc] initWithFormat: format
				    arguments: arguments] autorelease]);

	format = (OFConstantString *)[format stringByAppendingString: @"\r\n"];
	[_socket writeFormat: format
		   arguments: arguments];

	va_end(arguments);
}

- (void)sendStatus: (unsigned short)status
	 arguments: (OFArray OF_GENERIC(OFString *) *)arguments
{
	OFString *nickname = (_nickname != nil ? _nickname : @"*");
	OFString *message = messageForStatus(status);

	if (arguments == nil)
		[self sendLine: @":" IRC_HOST @" %03d %@ :%@",
				status, nickname, message];
	else {
		OFString *argumentsString =
		    [arguments componentsJoinedByString: @" "];
		[self sendLine: @":" IRC_HOST @" %03d %@ %@ :%@",
				status, nickname, argumentsString, message];
	}
}

- (void)checkHelloComplete
{
	if (_connected)
		return;

	if (_nickname == nil || _username == nil || _realname == nil)
		return;

	_connected = true;

	[self sendLine: @":" IRC_HOST @" 001 %@ :Welcome to MUC2IRC!",
			_nickname];
}

- (void)sendPresenceForChannel: (OFString *)channel
			  type: (OFString *)type
{
	XMPPJID *JID;
	OFXMLElement *history, *x;
	XMPPPresence *presence;

	channel = [channel substringWithRange:
	    of_range(1, channel.length - 1)];

	JID = [XMPPJID JID];
	JID.node = channel;
	JID.domain = MUC_HOST;
	JID.resource = _nickname;

	history = [OFXMLElement elementWithName: @"history"
				      namespace: XMPP_NS_MUC];
	[history addAttributeWithName: @"maxchars"
			  stringValue: @"0"];

	x = [OFXMLElement elementWithName: @"x"
				namespace: XMPP_NS_MUC];
	[x addChild: history];

	presence = [XMPPPresence presence];
	presence.to = JID;
	presence.type = type;
	[presence addChild: x];

	[_XMPPConnection sendStanza: presence];
}

- (void)joinChannel: (OFString *)channel
{
	if (![channel hasPrefix: @"#"]) {
		[self sendStatus: 403
		       arguments: [OFArray arrayWithObject: channel]];
		return;
	}

	[self sendPresenceForChannel: channel
				type: nil];
}

- (void)leaveChannel: (OFString *)channel
{
	if (![channel hasPrefix: @"#"]) {
		[self sendStatus: 403
		       arguments: [OFArray arrayWithObject: channel]];
		return;
	}

	[self sendPresenceForChannel: channel
				type: @"unavailable"];
}

- (void)sendMessage: (OFString *)message
	  toChannel: (OFString *)channel
{
	XMPPJID *JID;
	XMPPMessage *stanza;

	if (![channel hasPrefix: @"#"]) {
		[self sendStatus: 401
		       arguments: [OFArray arrayWithObject: channel]];
		return;
	}

	channel = [channel substringWithRange: of_range(1, channel.length - 1)];

	JID = [XMPPJID JID];
	JID.domain = MUC_HOST;
	JID.node = channel;

	stanza = [XMPPMessage messageWithType: @"groupchat"];
	stanza.to = JID;
	stanza.body = message;

	[_XMPPConnection sendStanza: stanza];
}
@end
