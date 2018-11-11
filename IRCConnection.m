#include <stdarg.h>

#import "IRCConnection.h"
#import "config.h"

@interface IRCConnection ()
- (bool)socket: (OF_KINDOF(OFTCPSocket *))sock
   didReadLine: (OFString *)line
       context: (id)context
     exception: (id)exception;
- (void)processLine: (OFString *)line;
- (void)sendLine: (OFConstantString *)format, ...;
- (void)sendStatus: (unsigned short)status
	 arguments: (OFArray OF_GENERIC(OFString *) *)arguments
	   message: (OFString *)message;
- (void)checkHelloComplete;
- (void)sendPresenceForChannel: (OFString *)channel
			  type: (OFString *)type;
- (void)joinChannel: (OFString *)channel;
- (void)leaveChannel: (OFString *)channel;
@end

@implementation IRCConnection
@synthesize nickname = _nickname, username = _username, realname = _realname;

+ (instancetype)connectionWithSocket: (OF_KINDOF(OFTCPSocket *))sock
{
	return [[[self alloc] initWithSocket: sock] autorelease];
}

- (instancetype)initWithSocket: (OF_KINDOF(OFTCPSocket *))sock
{
	self = [super init];

	@try {
		_socket = [sock retain];

		_XMPPConnection = [[XMPPConnection alloc] init];
		[_XMPPConnection setDomain: XMPP_HOST];
		[_XMPPConnection setResource: XMPP_RESOURCE];
		[_XMPPConnection setUsesAnonymousAuthentication: true];
		[_XMPPConnection addDelegate: self];
		[_XMPPConnection asyncConnect];

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
	    of_socket_address_ip_string([_socket remoteAddress], NULL));

	[self release];
}

- (void)connection: (XMPPConnection *)connection
     wasBoundToJID: (XMPPJID *)JID
{
	of_log(@"XMPP connection for %@ has JID %@",
	    of_socket_address_ip_string([_socket remoteAddress], NULL), JID);

	[_socket asyncReadLineWithTarget: self
				selector: @selector(socket:didReadLine:context:
					      exception:)
				 context: nil];
}

-   (void)connection: (XMPPConnection *)connection
  didReceivePresence: (XMPPPresence *)presence
{
	XMPPJID *from = [presence from];

	if ([[from domain] isEqual: MUC_HOST]) {
		if ([[presence type] isEqual: @"unavailable"])
			[self sendLine: @":%@ PART #%@",
					[from resource], [from node]];
		else if ([[presence type] isEqual: @"error"])
			[self sendLine: @":%@ KICK #%@ %@ :XMPP error presence",
					[from resource], [from node],
					[from resource]];
		/*
		 * We always fake our own join, so ignore presence for ourself.
		 */
		else if (![[from resource] isEqual: _nickname])
			[self sendLine: @":%@ JOIN #%@",
					[from resource], [from node]];
	}
}

-  (void)connection: (XMPPConnection *)connection
  didReceiveMessage: (XMPPMessage *)message
{
	XMPPJID *from = [message from];
	OFString *body = [message body];

	if ([[message type] isEqual: @"groupchat"] &&
	    [[from domain] isEqual: MUC_HOST] &&
	    ![[from resource] isEqual: _nickname]) {
		for (OFString *line in
		    [body componentsSeparatedByString: @"\n"])
			[self sendLine: @":%@ PRIVMSG #%@ :%@",
					[from resource], [from node], line];
	}
}

- (bool)socket: (OF_KINDOF(OFTCPSocket *))sock
   didReadLine: (OFString *)line
       context: (id)context
     exception: (id)exception
{
	if (exception != nil) {
		of_log(@"Exception in connection from %@",
		    of_socket_address_ip_string([sock remoteAddress], NULL));
		return false;
	}

	if (line == nil) {
		of_log(@"Connection from %@ closed",
		    of_socket_address_ip_string([sock remoteAddress], NULL));

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
	    of_socket_address_ip_string([_socket remoteAddress], NULL), line);

	if ([action isEqual: @"NICK"]) {
		OFString *nickname;

		if ([components count] < 2) {
			[self sendStatus: 431
			       arguments: nil
				 message: @"No nickname given"];
			return;
		}

		nickname = [components objectAtIndex: 1];
		if ([nickname hasPrefix: @":"])
			nickname = [nickname substringWithRange:
			    of_range(1, [nickname length] - 1)];

		if ([nickname length] == 0) {
			[self sendStatus: 431
			       arguments: nil
				 message: @"No nickname given"];
			return;
		}

		[self setNickname: nickname];
		[self checkHelloComplete];
	} else if ([action isEqual: @"USER"]) {
		OFString *username;
		OFString *hostname;
		OFString *servername;
		OFString *realname;

		if ([components count] < 5) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"USER"]
				 message: @"Not enough parameters"];
			return;
		}

		username = [components objectAtIndex: 1];
		hostname = [components objectAtIndex: 2];
		servername = [components objectAtIndex: 3];
		realname = [components objectAtIndex: 4];

		if ([realname hasPrefix: @":"])
			realname = [realname substringWithRange:
			    of_range(1, [realname length] - 1)];

		if ([realname length] == 0) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"USER"]
				 message: @"Not enough parameters"];
			return;
		}

		[self setUsername: username];
		[self setRealname: realname];
		[self checkHelloComplete];
	} else if ([action isEqual: @"JOIN"]) {
		if ([components count] < 2) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"JOIN"]
				 message: @"Not enough parameters"];
			return;
		}

		for (OFString *channel in [[components objectAtIndex: 1]
		    componentsSeparatedByString: @","])
			[self joinChannel: channel];
	} else if ([action isEqual: @"PART"]) {
		if ([components count] < 2) {
			[self sendStatus: 461
			       arguments: [OFArray arrayWithObject: @"LEAVE"]
				 message: @"Not enough parameters"];
			return;
		}

		for (OFString *channel in [[components objectAtIndex: 1]
		    componentsSeparatedByString: @","])
			[self leaveChannel: channel];
	} else if ([action isEqual: @"PRIVMSG"]) {
		OFString *channel;
		size_t messagePos;
		OFString *message;

		if ([components count] < 2) {
			[self sendStatus: 411
			       arguments: nil
				 message: @"No recipient given"];
			return;
		}

		if ([components count] < 3) {
			[self sendStatus: 412
			       arguments: nil
				 message: @"No text to send"];
			return;
		}

		channel = [components objectAtIndex: 1];

		messagePos = [action length] + [channel length] + 2;
		message = [line substringWithRange:
		    of_range(messagePos, [line length] - messagePos)];

		if ([message hasPrefix: @":"])
			message = [message substringWithRange:
			    of_range(1, [message length] - 1)];

		[self sendMessage: message
			toChannel: channel];
	} else
		[self sendStatus: 421
		       arguments: [OFArray arrayWithObject: action]
			 message: @"Unknown command"];
}

- (void)sendLine: (OFConstantString *)format, ...
{
	va_list arguments;
	va_start(arguments, format);

	of_log(@"[%@] < %@",
	    of_socket_address_ip_string([_socket remoteAddress], NULL),
	    [[[OFString alloc] initWithFormat: format
				    arguments: arguments] autorelease]);

	format = (OFConstantString *)[format stringByAppendingString: @"\r\n"];
	[_socket writeFormat: format
		   arguments: arguments];

	va_end(arguments);
}

- (void)sendStatus: (unsigned short)status
	 arguments: (OFArray OF_GENERIC(OFString *) *)arguments
	   message: (OFString *)message
{
	OFString *nickname = (_nickname != nil ? _nickname : @"*");

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
	XMPPPresence *presence;

	channel = [channel substringWithRange:
	    of_range(1, [channel length] - 1)];

	JID = [XMPPJID JID];
	JID.node = channel;
	JID.domain = MUC_HOST;
	JID.resource = _nickname;

	presence = [XMPPPresence presence];
	presence.to = JID;
	presence.type = type;

	[_XMPPConnection sendStanza: presence];
}

- (void)joinChannel: (OFString *)channel
{
	if (![channel hasPrefix: @"#"]) {
		[self sendStatus: 403
		       arguments: [OFArray arrayWithObject: channel]
			 message: @"No such channel"];
		return;
	}

	[self sendPresenceForChannel: channel
				type: nil];

	/*
	 * Immediately indicate to the client that the channel was joined -
	 * even if we could not.
	 *
	 * If we cannot join the channel, we just kick the user.
	 *
	 * The reason for this is that it makes handling presences
	 * significantly easier - we don't need to buffer all of them until we
	 * get our own presence, and can immediately convert presences to join
	 * messages.
	 */
	[self sendLine: @":%@ JOIN %@", _nickname, channel];
}

- (void)leaveChannel: (OFString *)channel
{
	if (![channel hasPrefix: @"#"]) {
		[self sendStatus: 403
		       arguments: [OFArray arrayWithObject: channel]
			 message: @"No such channel"];
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
		       arguments: [OFArray arrayWithObject: channel]
			 message: @"No such nick/channel"];
		return;
	}

	channel = [channel substringWithRange:
	    of_range(1, [channel length] - 1)];

	JID = [XMPPJID JID];
	JID.domain = MUC_HOST;
	JID.node = channel;

	stanza = [XMPPMessage messageWithType: @"groupchat"];
	stanza.to = JID;
	stanza.body = message;

	[_XMPPConnection sendStanza: stanza];
}
@end
