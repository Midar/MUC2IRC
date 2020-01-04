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
#import <ObjXMPP/ObjXMPP.h>

OF_ASSUME_NONNULL_BEGIN

@class XMPPConnection;

@interface IRCConnection: OFObject
{
	OFTCPSocket *_socket;
	XMPPConnection *_XMPPConnection;
	OFString *_Nullable _nickname, *_Nullable _username;
	OFString *_Nullable _realname;
	bool _handshakeDone;
	OFString *_Nullable _joinedChannel;
	OFMutableSet OF_GENERIC(OFString *) *_nicknamesInChannel;
}

@property OF_NULLABLE_PROPERTY (copy, nonatomic) OFString *nickname, *username;
@property OF_NULLABLE_PROPERTY (copy, nonatomic) OFString *realname;

+ (instancetype)connectionWithSocket: (OFTCPSocket *)sock;
- (instancetype)initWithSocket: (OFTCPSocket *)sock OF_DESIGNATED_INITIALIZER;
@end

OF_ASSUME_NONNULL_END
