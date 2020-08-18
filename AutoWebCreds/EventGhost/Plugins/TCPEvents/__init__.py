# This file is part of EventGhost.
# Copyright (C) 2005 Lars-Peter Voss <bitmonster@eventghost.org>
#
# EventGhost is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# EventGhost is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with EventGhost; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
# This plugin is a tcp server and client that can send and receive data.
# Data can be events, request data, send data.
# This plugin is based on the Network Event Receiver and Sender plugins by bitmonster, and is compatible with them.
#
# $LastChangedDate: 2015-11-18 3:30:00 +0100$
# $LastChangedRevision: 4 $
# $LastChangedBy: per1234 $


README = """\
<p>Send and receive events and data over a network. TCPEvents was created as a replacement for the very limited Network Event Sender and Receiver plugins and adds many enhancements. It is fully compatible with the original Network Event Sender/Receiver plugins. This is a fork of the <a href="http://www.eventghost.net/forum/viewtopic.php?t=2944">original TCPEvents</a> which appears to have been abandoned. It fixes a security vulnerability and adds some useful features.</p>


<h4></a>Usage</h4>
<p>You can use {} in most configuration fields to have TCPEvents replace the content with the corresponding variable.</p>

<ul>
<li><p><strong>Plugin Configuration</strong>:</p>
<ul>
<li><strong>TCP/IP Port</strong> - The port used for receiving.</li>
<li><strong>Password</strong> - The password must match the password used by the sender. Leave the password field blank to disable authentication. Unauthenticated operation is not supported by the Network Event Sender/Receiver plugin.</li>
<li><strong>Default Event Prefix</strong> - The prefix to use on received events unless a prefix is specified by the sender.</li>
<li><strong>Add source IP to the payload</strong> - If checked the sender's IP address will be included with the payload of received events.</li>
<li><strong>Connection Timeout(seconds)</strong> - Maximum number of seconds to attempt to connect to the server before the event send fails. Any other operation in EventGhost will be blocked until the send is completed or times out so it is important to find the smallest value that still allows for reliable communication.</li>
<li><strong>Communication Timeout(seconds)</strong> - Maximum number of seconds to attempt communication with the server before the event send fails.</li>
</ul></li>

<li><p><strong>Send an Event</strong></p>
<ul>
<li><strong>Address</strong> - The IP address to send the event to.</li>
<li><strong>TCP/IP port</strong> - The port to send the event to. This should match the port setting in the plugin configuration of the receiver.</li>
<li><strong>Password</strong> - Leave blank to disable authentication.</li>
<li><strong>Prefix</strong> - Prefix of the sent event. If the prefix is not specified then the default prefix specified in the plugin configuration of the receiver will be used. Custom prefix is not supported by the Network Event Sender/Receiver plugin.</li>
<li><strong>Suffix</strong> - Suffix of the sent event.</li>
<li><strong>Payload(Python expr.)</strong> - If you want to send a plain text string write it between quotes. You can send/receive payload of various types(strings, numbers, lists, dicts, tuples, datetime, etc.).</li>
</ul></li>

<li><p><strong>Send Data</strong> - When sending data, the server won't produce any event. It will only store it with the provided name. The stored data can be retrieved at any time using the data name. This action is not supported by the Network Event Sender/Receiver plugins. See the <strong>Send an Event section</strong> for documentation of duplicate fields.</p>
<ul>
<li><strong>Name</strong> - The name is used to retrieve received data.</li>
<li><strong>Data(Python expression)</strong> - Data to send.</li>
</ul></li>

<li><p><strong>Retrieve Received Data</strong> - The retrieved data stored under the name is returned as eg.result. This action is not supported by the Network Event Sender/Receiver plugins.</p>
<ul>
<li><strong>Name of the data to retrieve</strong> - Use the data name specified in the Send Data action.</li>
</ul></li>

<li><p><strong>Request Data from a remote host</strong> - The response is returned as eg.result. No event is created. This action is not supported by the Network Event Sender/Receiver plugins. See the
<strong>Send an Event</strong> section for documentation of duplicate fields.</p>
<ul>
<li><strong>Python expression</strong> - This expression is evaluated on the receiver and the result is sent back</li>
</ul></li>
</ul>


<h4>Acknowledgements</h4>
<ul>
<li>TCPEvents is based on the Network Event Sender and Receiver plugins by bitmonster, the creator of EventGhost.</li>
<li>TCPEvents was written by EventGhost forum member miljbee.</li>
</ul>


<h4>Changelog</h4>
<ul>
<li>see <a href="http://www.eventghost.net/forum/viewtopic.php?t=2944">http://www.eventghost.net/forum/viewtopic.php?t=2944</a> for the original changelog</li>
<li>Security vulnerability patch</li>
<li>Unauthenticated option</li>
<li>Set timeouts via configuration</li>
</ul>
"""


import eg

eg.RegisterPlugin(
    name="TCP Events",
    url="https://github.com/per1234/TCPEvents",
    description="Receives and sends events and/or data over TCP",
    help=README,
    version="2.1." + "$LastChangedRevision: 0 $".split()[1],
    author="miljbee",
    canMultiLoad=True,
    icon=(
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QAAAAAAAD5Q7t/"
        "AAAACXBIWXMAAAsSAAALEgHS3X78AAAAB3RJTUUH1gIQFgQb1MiCRwAAAVVJREFUOMud"
        "kjFLw2AQhp8vif0fUlPoIgVx6+AgopNI3fwBViiIoOAgFaugIDhUtP4BxWDs4CI4d3MR"
        "cSyIQ1tDbcHWtjFI4tAWG5pE8ca7997vnrtP4BOZvW0dSBAcZ0pAMTEzPUs4GvMsVkvP"
        "6HktGWRAOBpjIXVNKOSWWdYXN7lFAAINhBCEQgqxyTHAAQQAD/dFbLurUYJYT7P7TI2C"
        "VavwIiZodyyaH6ZLo/RZVTXiOYVhGOh5jcpbq5eRAXAc5wdBVSPMLR16GtxdbgJgN95d"
        "OxicACG6bPH4uIu1UHjE7sFqR/NDVxhaoixLvFYbtDufNFtu1tzxgdeAaZfBU7ECTvd1"
        "WRlxsa4sp1ydkiRxkstmlEFRrWT4nrRer3vmlf6mb883fK8AoF1d+Bqc6Xkt+cufT6e3"
        "dnb9DJJrq+uYpunZ2WcFfA0ol8v8N5Qgvr/EN8Lzfbs+L0goAAAAAElFTkSuQmCC"
    ),
    guid='{198090B7-0574-4F91-B2E7-1AF5BB37E2DE}'
)


import sys
import wx
import asynchat
import asyncore
from hashlib import md5
import random
import socket
import threading
import time
import datetime


class Text:
    port = "TCP/IP Port: "
    address = "Address: "
    password = "Password: "
    eventPrefix = "Default Event Prefix: "
    prefix = "Prefix: "
    suffix = "Suffix: "
    payload = "Payload (Python expr.): "
    tcpBox = "TCP/IP Settings"
    securityBox = "Security"
    eventGenerationBox = "Event generation"
    sourceIP = "Add source IP to the payload: "
    dataName = "Name"
    dataToSend = "Data (python expression): "
    dataBox = "Data"
    dataToReceive = "Python expression: "
    timeoutBox = "Send Timeout Duration"
    connectionTimeout = "Connection Timeout(seconds): "
    communicationTimeout = "Communication Timeout(seconds): "


class DefaultValues:
    defaultTimeout = 5.0


DEBUG = False
if DEBUG:
    log = eg.Print
else:
    def log(dummyMesg):
        pass


class TCPEvents(eg.PluginBase):
    text = Text
    receivedData = {}

    def __init__(self):
        self.AddEvents()
        self.AddAction(SendEvent)
        self.AddAction(SendData)
        self.AddAction(GetData)
        self.AddAction(RequestData)
        self.server = None

    def __start__(self, port, password, prefix, inclSrcIP, conTimeout=DefaultValues.defaultTimeout, comTimeout=DefaultValues.defaultTimeout):
        self.lock = threading.Lock()
        self.port = port
        self.password = password
        self.info.eventPrefix = prefix
        self.prefix = prefix
        self.includeSourceIP = inclSrcIP
        self.connectionTimeout = conTimeout
        self.communicationTimeout = comTimeout
        try:
            self.server = Server(self.port, self.password, self)
        except socket.error, exc:
            eg.PrintError("Exception in TCPEvents.__start__")
            raise self.Exception(exc[1])

    def __stop__(self):
        if self.server:
            self.server.close()
        self.server = None

    def __close__(self):
        if self.server:
            self.server.close()
        self.server = None

    def Configure(self, port=1024, password="", prefix="TCP", inclSrcIP=True, conTimeout=DefaultValues.defaultTimeout, comTimeout=DefaultValues.defaultTimeout):
        text = self.text
        panel = eg.ConfigPanel()

        portCtrl = panel.SpinIntCtrl(port, max=65535)
        passwordCtrl = panel.TextCtrl(password, style=wx.TE_PASSWORD)
        eventPrefixCtrl = panel.TextCtrl(prefix)
        sourceIPCtrl = panel.CheckBox(inclSrcIP)
        connectionTimeoutCtrl = panel.SpinNumCtrl(conTimeout, integerWidth=2, increment=0.01)
        communicationTimeoutCtrl = panel.SpinNumCtrl(comTimeout, integerWidth=2, increment=0.01)
        st1 = panel.StaticText(text.port)
        st2 = panel.StaticText(text.password)
        st3 = panel.StaticText(text.eventPrefix)
        st4 = panel.StaticText(text.sourceIP)
        st5 = panel.StaticText(text.connectionTimeout)
        st6 = panel.StaticText(text.communicationTimeout)
        eg.EqualizeWidths((st1, st2, st3, st4, st5, st6))
        box1 = panel.BoxedGroup(text.tcpBox, (st1, portCtrl))
        box2 = panel.BoxedGroup(text.securityBox, (st2, passwordCtrl))
        box3 = panel.BoxedGroup(text.eventGenerationBox, (st3, eventPrefixCtrl), (st4, sourceIPCtrl))
        box4 = panel.BoxedGroup(text.timeoutBox, (st5, connectionTimeoutCtrl), (st6, communicationTimeoutCtrl))
        panel.sizer.AddMany([
            (box1, 0, wx.EXPAND),
            (box2, 0, wx.EXPAND | wx.TOP, 10),
            (box3, 0, wx.EXPAND | wx.TOP, 10),
            (box4, 0, wx.EXPAND | wx.TOP, 10),
        ])

        while panel.Affirmed():
            panel.SetResult(
                portCtrl.GetValue(),
                passwordCtrl.GetValue(),
                eventPrefixCtrl.GetValue(),
                sourceIPCtrl.GetValue(),
                connectionTimeoutCtrl.GetValue(),
                communicationTimeoutCtrl.GetValue()
            )


class ServerHandler(asynchat.async_chat):
    """Telnet engine class. Implements command line user interface."""

    def __init__(self, sock, addr, password, plugin, server):
        log("Server Handler inited")
        self.plugin = plugin

        # Call constructor of the parent class
        asynchat.async_chat.__init__(self, sock)

        # Set up input line terminator
        self.set_terminator('\n')

        # Initialize input data buffer
        self.data = ''
        self.ip = addr[0]
        self.payload = [self.ip] if self.plugin.includeSourceIP else []
        if (password != ""):
            self.state = self.state1
            self.cookie = hex(random.randrange(65536))
            self.cookie = self.cookie[len(self.cookie) - 4:]
            self.hex_md5 = md5(self.cookie + ":" + password).hexdigest().upper()
        else:
            self.clientType = "TCPEvents"
            self.state = self.state3
        self.receivedDataName = ""

    def handle_close(self):
        self.plugin.EndLastEvent()
        asynchat.async_chat.handle_close(self)

    def collect_incoming_data(self, data):
        """Put data read from socket to a buffer"""
        # Collect data in input buffer
        log("<<" + repr(data))
        self.data = self.data + data

    if DEBUG:
        def push(self, data):
            log(">>", repr(data))
            asynchat.async_chat.push(self, data)

    def found_terminator(self):
        """
        This method is called by asynchronous engine when it finds
        command terminator in the input stream
        """
        # Take the complete line
        line = self.data

        # Reset input buffer
        self.data = ''

        # call state handler
        self.state(line)

    def initiate_close(self):
        try:
            self.push("close\n")
            self.close_when_done()
        except:
            eg.PrintError("Error in ServerHandler.initiate_close(push/close_when_done): " + str(sys.exc_info()))
        # asynchat.async_chat.handle_close(self)
        self.plugin.EndLastEvent()
        self.state = self.state1
        try:
            self.close()
        except:
            eg.PrintError("Error in ServerHandler.initiate_close (close)" + str(sys.exc_info()))

    def state1(self, line):
        """get keyword "quintessence\n" and send cookie"""
        if line == "quintessence":
            self.state = self.state2
            self.push(self.cookie + "\n")
        else:
            self.initiate_close()

    def state2(self, line):
        """get MD5 digest"""
        line = line.strip()
        digest = line.strip()[-32:]
        if digest == "":
            pass
        elif digest.upper() == self.hex_md5:
            if len(line) > 32:
                self.clientType = "TCPEvents" if line[:-32] == "TCPEvents" else "Network Event Sender"
            else:
                self.clientType = "Network Event Sender"
            # print "From Server: clientType = " + self.clientType
            self.push(" accept\n")
            self.state = self.state3
        else:
            eg.PrintError("NetworkReceiver MD5 error")
            self.initiate_close()

    def state3(self, line):
        line = line.decode(eg.systemEncoding)
        if line == "close":
            self.initiate_close()
        elif line[:8] == "payload ":
            if self.clientType == "TCPEvents":
                try:
                    self.payload.append(eval(line[8:])[0])
                except:
                    eg.PrintError("Unable to eval the payload, receiving the full string")
                    self.payload.append(line[8:])
            else:
                self.payload.append(line[8:])
        elif self.clientType == "TCPEvents" and line[:12] == "dataRequest ":
            dataRequest = line[12:]
            try:
                result = []
                result.append(eval(str(eval(dataRequest)[0])))
            except:
                eg.PrintError("Unable to respond to dataRequest: " + dataRequest + ". Closing the socket.")
                result = None
                self.initiate_close()
            if result is not None:
                self.push("result " + str(result) + "\n")
                self.initiate_close()
        elif self.clientType == "TCPEvents" and line[:9] == "dataName ":
            self.receivedDataName = str(line[9:])
        elif self.clientType == "TCPEvents" and line[:5] == "data ":
            if self.receivedDataName != "":
                receivedData = eval(line[5:])[0]
                self.plugin.receivedData[self.receivedDataName] = receivedData
            else:
                eg.PrintError("Data received before dataName. Closing the socket.")
            self.initiate_close()
        else:
            if line == "ButtonReleased":
                self.plugin.EndLastEvent()
            else:
                if len(self.payload) > 0 and self.payload[-1] == "withoutRelease":
                    self.payload.remove("withoutRelease")

                    self.plugin.lock.acquire()
                    try:
                        if line.find(".") == 0:
                            line = line[1:]
                        if line.find(".") == len(line) - 1:
                            line = line[:-1]
                        if line.find(".") > 0:
                            self.plugin.info.eventPrefix = line[:line.find(".")]
                            line = line[line.find(".") + 1:]
                        else:
                            self.plugin.info.eventPrefix = self.plugin.prefix

                        if len(self.payload) == 0:
                            self.plugin.TriggerEnduringEvent(line, None)
                        elif len(self.payload) == 1:
                            self.plugin.TriggerEnduringEvent(line, self.payload[0])
                        else:
                            self.plugin.TriggerEnduringEvent(line, self.payload)
                    finally:
                        self.plugin.lock.release()
                else:
                    self.plugin.lock.acquire()
                    try:
                        if line.find(".") == 0:
                            line = line[1:]
                        if line.find(".") == len(line) - 1:
                            line = line[:-1]
                        if line.find(".") > 0:
                            self.plugin.info.eventPrefix = line[:line.find(".")]
                            line = line[line.find(".") + 1:]
                        else:
                            self.plugin.info.eventPrefix = self.plugin.prefix

                        if len(self.payload) == 0:
                            self.plugin.TriggerEvent(line, None)
                        elif len(self.payload) == 1:
                            self.plugin.TriggerEvent(line, self.payload[0])
                        else:
                            self.plugin.TriggerEvent(line, self.payload)
                    finally:
                        self.plugin.lock.release()

            self.payload = [self.ip] if self.plugin.includeSourceIP else []


class Server(asyncore.dispatcher):

    def __init__(self, port, password, handler):
        try:
            self.handler = handler
            self.password = password

            # Call parent class constructor explicitly
            asyncore.dispatcher.__init__(self)

            # Create socket of requested type
            self.create_socket(socket.AF_INET, socket.SOCK_STREAM)

            # restart the asyncore loop, so it notices the new socket
            eg.RestartAsyncore()

            # Set it to re-use address
            # self.set_reuse_addr()
            # self.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            # Bind to all interfaces of this host at specified port
            self.bind(('', port))

            # Start listening for incoming requests. The parameter is the maximum number of queued connections.
            self.listen(5)
        except:
            eg.PrintError("TCPEvents: Error in Server.__init__: " + str(sys.exc_info()))

    def handle_accept(self):
        """Called by asyncore engine when new connection arrives"""
        # Accept new connection
        log("handle_accept")
        try:
            (sock, addr) = self.accept()
            ServerHandler(
                sock,
                addr,
                self.password,
                self.handler,
                self
            )
        except:
            eg.PrintError("TCPEvents: Error in handle accept: " + str(sys.exc_info()))


class SendEvent(eg.ActionBase):

    name = "Send an Event"

    def __call__(self, destIP, destPort, passwd, evtPref, evtSuf, evtPayloadStr, evtPayload):
        if destIP == "":
            eg.PrintError("Destination address field left blank.")
        self.host = eg.ParseString(destIP)
        self.port = destPort
        self.password = eg.ParseString(passwd)
        self.eventPrefix = eg.ParseString(evtPref)
        self.eventSuffix = eg.ParseString(evtSuf)
        if (evtPayloadStr is not None) and (evtPayloadStr != ""):
            try:
                self.eventPayload = eval(evtPayloadStr)
            except:
                eg.PrintError("Unable to evaluate the payload. Payload must be a valid python expression(example: \"some\\\"Text\\\"\"). Your string will be sent unevaluated.")
                self.eventPayload = evtPayloadStr
        else:
            self.eventPayload = evtPayload
        return self.Send()

    def Configure(self, destIP="", destPort=1024, passwd="", evtPref="", evtSuf="{eg.result}", evtPayloadStr="", evtPayload=None):
        text = Text
        panel = eg.ConfigPanel()

        # if evtPref == "":
        #    evtPref = self.plugin.prefix

        addrCtrl = panel.TextCtrl(destIP)
        portCtrl = panel.SpinIntCtrl(destPort, max=65535)
        passwordCtrl = panel.TextCtrl(passwd, style=wx.TE_PASSWORD)
        evtPrefCtrl = panel.TextCtrl(evtPref)
        evtSufCtrl = panel.TextCtrl(evtSuf)
        evtPldCtrl = panel.TextCtrl(evtPayloadStr)

        st1 = panel.StaticText(text.address)
        st2 = panel.StaticText(text.port)
        st3 = panel.StaticText(text.password)
        st4 = panel.StaticText(text.prefix)
        st5 = panel.StaticText(text.suffix)
        st6 = panel.StaticText(text.payload)

        eg.EqualizeWidths((st1, st2, st3, st4, st5, st6))

        box1 = panel.BoxedGroup(text.tcpBox, (st1, addrCtrl), (st2, portCtrl))
        box2 = panel.BoxedGroup(text.securityBox, (st3, passwordCtrl))
        box3 = panel.BoxedGroup(
            text.eventGenerationBox,
            (st4, evtPrefCtrl),
            (st5, evtSufCtrl),
            (st6, evtPldCtrl)
        )

        panel.sizer.AddMany([
            (box1, 0, wx.EXPAND),
            (box2, 0, wx.EXPAND | wx.TOP, 10),
            (box3, 0, wx.EXPAND | wx.TOP, 10),
        ])

        while panel.Affirmed():
            panel.SetResult(
                addrCtrl.GetValue(),
                portCtrl.GetValue(),
                passwordCtrl.GetValue(),
                evtPrefCtrl.GetValue(),
                evtSufCtrl.GetValue(),
                evtPldCtrl.GetValue(),
                None
            )

    def Send(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(self.plugin.connectionTimeout)
        try:
            sock.connect((self.host, self.port))
            sock.settimeout(self.plugin.communicationTimeout)
            # First wake up the server, for security reasons it does not
            # respond by itself it needs this string, why this odd word ?
            # well if someone is scanning ports "connect" would be very
            # obvious this one you'd never guess :-)
            serverType = "TCPEvents"
            if (self.password != ""):
                sock.sendall("quintessence\n\r")
                # The server now returns a cookie, the protocol works like the
                # APOP protocol. The server gives you a cookie you add :<password>
                # calculate the MD5 digest out of this and send it back
                # if the digests match you are in.
                # We do this so that no one can listen in on our password exchange
                # much safer than plain text.

                cookie = sock.recv(128)

                # Trim all enters and whitespaces off
                cookie = cookie.strip()

                # Combine the token <cookie>:<password>
                token = cookie + ":" + self.password

                # Calculate the digest
                digest = md5(token).hexdigest()

                # add the enters
                digest = digest + "\n"

                # Send it to the server
                sock.sendall("TCPEvents" + digest)

                # Get the answer
                answer = sock.recv(512)

                # If the password was correct and you are allowed to connect
                # to the server, you'll get "accept"
                if (answer.strip() != "accept"):
                    sock.close()
                    return False
                elif (answer.strip("\n") == " accept"):
                    serverType = "TCPEvents"
                else:
                    serverType = "Network Event Receiver"
                # print "From Client: Server Type = " + serverType

            # now just pipe those commands to the server
            if (self.eventPrefix is not None) and (len(self.eventPrefix) > 0) and (serverType == "TCPEvents"):
                eventString = self.eventPrefix + "." + self.eventSuffix
            else:
                eventString = self.eventSuffix

            if (self.eventPayload is not None):
                # payload will be passed to eval by the server so that we can get back the exact same object(s) we have here
                srcData = self.eventPayload
                if serverType == "TCPEvents":
                    srcDataLst = []
                    srcDataLst.append(srcData)
                    srcDataStr = unicode(srcDataLst)
                else:
                    srcDataStr = str(srcData)
                sock.sendall(
                    (u'payload ' + srcDataStr + u'\n').encode("utf-8")
                )

            if serverType != "TCPEvents":
                sock.sendall("payload withoutRelease\n")
            sock.sendall((eventString + "\n").encode("utf-8"))
            # tell the server that we are done nicely.
            sock.sendall("close\n")
            sock.close()
            return [eventString, srcData if (self.eventPayload is not None) else None]
        except:
            if eg.debugLevel:
                eg.PrintTraceback()
            sock.close()
            self.PrintError("An error occurred while sending your event")
            return None


class SendData(eg.ActionBase):
    name = "Send Data"

    def __call__(self, destIP, destPort, passwd, dataName, dataToEval, data):
        if destIP == "":
            eg.PrintError("Destination address field is blank")
        self.host = eg.ParseString(destIP)
        self.port = destPort
        self.password = eg.ParseString(passwd)
        self.dataName = eg.ParseString(dataName)
        if (dataToEval is not None) and (dataToEval != ""):
            try:
                self.data = eval(dataToEval)
            except:
                eg.PrintError("Error evaluating " + str(dataToEval) + ". Sending None to the server.")
                self.data = None
        else:
            self.data = data
        return self.Send()

    def Configure(self, destIP="", destPort=1024, passwd="", dataName="data1", dataToEval="", data=None):
        text = Text
        panel = eg.ConfigPanel()

        addrCtrl = panel.TextCtrl(destIP)
        portCtrl = panel.SpinIntCtrl(destPort, max=65535)
        passwordCtrl = panel.TextCtrl(passwd, style=wx.TE_PASSWORD)
        dataNameCtrl = panel.TextCtrl(dataName)
        dataCtrl = panel.TextCtrl(dataToEval)

        st1 = panel.StaticText(text.address)
        st2 = panel.StaticText(text.port)
        st3 = panel.StaticText(text.password)
        st4 = panel.StaticText(text.dataName)
        st5 = panel.StaticText(text.dataToSend)
        eg.EqualizeWidths((st1, st2, st3, st4, st5))

        box1 = panel.BoxedGroup(text.tcpBox, (st1, addrCtrl), (st2, portCtrl))
        box2 = panel.BoxedGroup(text.securityBox, (st3, passwordCtrl))
        box3 = panel.BoxedGroup(text.dataBox, (st4, dataNameCtrl), (st5, dataCtrl))

        panel.sizer.AddMany([
            (box1, 0, wx.EXPAND),
            (box2, 0, wx.EXPAND | wx.TOP, 10),
            (box3, 0, wx.EXPAND | wx.TOP, 10),
        ])

        while panel.Affirmed():
            panel.SetResult(
                addrCtrl.GetValue(),
                portCtrl.GetValue(),
                passwordCtrl.GetValue(),
                dataNameCtrl.GetValue(),
                dataCtrl.GetValue(),
                None
            )

    def Send(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        #self.socket = sock
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(self.plugin.connectionTimeout)
        try:
            sock.connect((self.host, self.port))
            sock.settimeout(self.plugin.communicationTimeout)
            # First wake up the server, for security reasons it does not
            # respond by itself it needs this string, why this odd word ?
            # well if someone is scanning ports "connect" would be very
            # obvious this one you'd never guess :-)
            serverType = "TCPEvents"
            if (self.password != ""):
                sock.sendall("quintessence\n\r")

                # The server now returns a cookie, the protocol works like the
                # APOP protocol. The server gives you a cookie you add :<password>
                # calculate the MD5 digest out of this and send it back
                # if the digests match you are in.
                # We do this so that no one can listen in on our password exchange
                # much safer than plain text.

                cookie = sock.recv(128)

                # Trim all enters and whitespaces off
                cookie = cookie.strip()

                # Combine the token <cookie>:<password>
                token = cookie + ":" + self.password

                # Calculate the digest
                digest = md5(token).hexdigest()

                # add the enters
                digest = digest + "\n"

                # Send it to the server
                sock.sendall("TCPEvents" + digest)

                # Get the answer
                answer = sock.recv(512)

                # If the password was correct and you are allowed to connect
                # to the server, you'll get "accept"
                if (answer.strip() != "accept"):
                    sock.close()
                    return False
                elif (answer.strip("\n") == " accept"):
                    serverType = "TCPEvents"
                else:
                    serverType = "Network Event Receiver"

            if serverType == "TCPEvents":
                sock.sendall("dataName %s\n" % self.dataName)
                srcData = self.data
                srcDataList = []
                srcDataList.append(self.data)
                srcDataStr = str(srcDataList)
                sock.sendall("data " + srcDataStr + "\n")
                sock.sendall("close\n")
                sock.close()
            else:
                eg.PrintError("The server isn't a TCPEvents server(is it a Network Event Receiver?). Your data will be sent in the payload.")
                sock.sendall("payload %s\n" % self.dataName.encode(eg.systemEncoding))
                sock.sendall("payload %s\n" % str(self.data).encode(eg.systemEncoding))
                sock.sendall("payload withoutRelease\n")
                sock.sendall("SendData".encode(eg.systemEncoding) + "\n")
                # tell the server that we are done nicely.
                sock.sendall("close\n")
                sock.close()
                return True
        except:
            if eg.debugLevel:
                eg.PrintTraceback()
            sock.close()
            self.PrintError("NetworkSender failed")
            return None


class GetData(eg.ActionBase):
    name = "Retrieve Received Data"

    def __call__(self, dataName):
        if dataName in self.plugin.receivedData:
            result = self.plugin.receivedData[dataName]
        else:
            eg.PrintError(str(dataName) + " not found. Check the Data Name and make sure this data has been remotely set. Returning None.")
            result = None
        return result

    def Configure(self, dataName="data1"):
        panel = eg.ConfigPanel()
        dataNameCtrl = panel.TextCtrl(dataName)
        st1 = panel.StaticText("Name of the data to retrieve: ")
        box1 = panel.BoxedGroup("Name", (st1, dataNameCtrl))
        panel.sizer.AddMany([
            (box1, 0, wx.EXPAND),
        ])

        while panel.Affirmed():
            panel.SetResult(
                dataNameCtrl.GetValue()
            )


class RequestData(eg.ActionBase):
    name = "Request Data from a remote host"

    def __call__(self, destIP, destPort, passwd, data):
        if destIP == "":
            eg.PrintError("Destination address field is blank")
        self.host = eg.ParseString(destIP)
        self.port = destPort
        self.password = eg.ParseString(passwd)
        self.data = data
        return self.Send()

    def Configure(self, destIP="", destPort=1024, passwd="", data=""):
        text = Text
        panel = eg.ConfigPanel()

        addrCtrl = panel.TextCtrl(destIP)
        portCtrl = panel.SpinIntCtrl(destPort, max=65535)
        passwordCtrl = panel.TextCtrl(passwd, style=wx.TE_PASSWORD)
        dataCtrl = panel.TextCtrl(data)

        st1 = panel.StaticText(text.address)
        st2 = panel.StaticText(text.port)
        st3 = panel.StaticText(text.password)
        st4 = panel.StaticText(text.dataToReceive)
        eg.EqualizeWidths((st1, st2, st3, st4))

        box1 = panel.BoxedGroup(text.tcpBox, (st1, addrCtrl), (st2, portCtrl))
        box2 = panel.BoxedGroup(text.securityBox, (st3, passwordCtrl))
        box3 = panel.BoxedGroup(text.dataBox, (st4, dataCtrl))

        panel.sizer.AddMany([
            (box1, 0, wx.EXPAND),
            (box2, 0, wx.EXPAND | wx.TOP, 10),
            (box3, 0, wx.EXPAND | wx.TOP, 10),
        ])

        while panel.Affirmed():
            panel.SetResult(
                addrCtrl.GetValue(),
                portCtrl.GetValue(),
                passwordCtrl.GetValue(),
                dataCtrl.GetValue(),
            )

    def Send(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        #self.socket = sock
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(self.plugin.connectionTimeout)
        try:
            sock.connect((self.host, self.port))
            sock.settimeout(self.plugin.communicationTimeout)
            # First wake up the server, for security reasons it does not
            # respond by itself it needs this string, why this odd word ?
            # well if someone is scanning ports "connect" would be very
            # obvious this one you'd never guess :-)
            serverType = "TCPEvents"
            if (self.password != ""):
                sock.sendall("quintessence\n\r")

                # The server now returns a cookie, the protocol works like the
                # APOP protocol. The server gives you a cookie you add :<password>
                # calculate the MD5 digest out of this and send it back
                # if the digests match you are in.
                # We do this so that no one can listen in on our password exchange
                # much safer than plain text.

                cookie = sock.recv(128)

                # Trim all enters and whitespaces off
                cookie = cookie.strip()

                # Combine the token <cookie>:<password>
                token = cookie + ":" + self.password

                # Calculate the digest
                digest = md5(token).hexdigest()

                # add the enters
                digest = digest + "\n"

                # Send it to the server
                sock.sendall("TCPEvents" + digest)

                # Get the answer
                answer = sock.recv(512)

                # If the password was correct and you are allowed to connect
                # to the server, you'll get "accept"
                if (answer.strip() != "accept"):
                    sock.close()
                    return False
                elif (answer.strip("\n") == " accept"):
                    serverType = "TCPEvents"
                else:
                    serverType = "Network Event Receiver"

            if serverType == "TCPEvents":
                dataRequest = []
                dataRequest.append(self.data)
                sock.sendall("dataRequest %s\n" % str(dataRequest))
                count = 0
                answer = ""
                try:
                    close = False
                    while (answer.find("\n") < 0) and count < 128:
                        answer += sock.recv(512)
                        count += 1
                    close = (answer.find("close\n") >= 0)
                    answer = answer[:answer.find("\n")]
                except:
                    pass
                try:
                    if not close:
                        sock.sendall("close\n")
                finally:
                    sock.close()
                answer = answer.strip()
                if answer[:7] == "result ":
                    try:
                        result = eval(answer[7:])[0]
                    except:
                        eg.PrintError("Can not eval the response from the server: " + answer + ". Returning None.")
                        result = None
                else:
                    eg.PrintError("The server didn't send back a response. It might not be able to evaluate the request (" + self.data + "==>" + answer + ").")
                    result = None
            else:
                eg.PrintError("The server isn't a TCPEvents server(is it a Network Event Receiver?). Your request will be sent in the Payload")
                sock.sendall("payload %s\n" % str(self.data).encode(eg.systemEncoding))
                sock.sendall("payload withoutRelease\n")
                sock.sendall("RequestData".encode(eg.systemEncoding) + "\n")
                # tell the server that we are done nicely.
                sock.sendall("close\n")
                sock.close()
                result = None
            return result
        except:
            if eg.debugLevel:
                eg.PrintTraceback()
            sock.close()
            self.PrintError("NetworkSender failed")
            return None
