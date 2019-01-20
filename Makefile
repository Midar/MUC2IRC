all:
	@objfw-compile --package ObjXMPP -o muc2irc	\
		IRCConnection.m				\
		MUC2IRC.m

clean:
	rm -f *~ *.o muc2irc
