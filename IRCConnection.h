#import <ObjFW/ObjFW.h>
#import <ObjXMPP/ObjXMPP.h>

OF_ASSUME_NONNULL_BEGIN

@class XMPPConnection;

@interface IRCConnection: OFObject <XMPPConnectionDelegate>
{
	OF_KINDOF(OFTCPSocket *) _socket;
	XMPPConnection *_XMPPConnection;
	OFString *_Nullable _nickname, *_Nullable _username;
	OFString *_Nullable _realname;
	bool _connected;
	OFMutableDictionary OF_GENERIC(OFString *,
	    OFMutableSet OF_GENERIC(OFString *) *) *_nicknamesInChannels;
	OFMutableSet OF_GENERIC(OFString *) *_joinedChannels;
}

@property OF_NULLABLE_PROPERTY (copy, nonatomic) OFString *nickname, *username;
@property OF_NULLABLE_PROPERTY (copy, nonatomic) OFString *realname;

+ (instancetype)connectionWithSocket: (OF_KINDOF(OFTCPSocket *))sock;
- (instancetype)initWithSocket: (OF_KINDOF(OFTCPSocket *))sock
    OF_DESIGNATED_INITIALIZER;
@end

OF_ASSUME_NONNULL_END
