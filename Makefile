all:
	@objfw-compile -lobjxmpp -o muc2irc	\
		IRCConnection.m			\
		MUC2IRC.m

clean:
	rm -f *~ *.o muc2irc
