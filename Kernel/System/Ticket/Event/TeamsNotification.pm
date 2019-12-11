# --
# (TeamsNotification.pm) - sends a JSON payload to a Microsoft Teams webhook
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Ticket::Event::TeamsNotification;

use strict;
use utf8;
use Encode;
use warnings;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

use LWP::UserAgent;
use HTTP::Request::Common;

our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::System::Log
    Kernel::System::Ticket
    Kernel::System::Ticket::Article
    Kernel::System::User
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketObject  = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $UserObject    = $Kernel::OM->Get('Kernel::System::User');
    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'Run TeamsNotification event module',
    );

    # check needed stuff
    for my $NeededParam (qw(Event Data Config UserID)) {
        if ( !$Param{$NeededParam} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $NeededParam!",
            );
            return;
        }
    }

    for my $NeededData (qw(TicketID ArticleID)) {
        if ( !$Param{Data}->{$NeededData} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $NeededData in Data!",
            );
            return;
        }
    }

    # get ticket attribute matches
    my %Article = $ArticleObject->ArticleGet(
        ArticleID    => $Param{Data}->{ArticleID},
        TicketID     => $Param{Data}->{TicketID},
        Subject      => $Param{Data}->{Subject},
        From         => $Param{Data}->{From},
        SenderType   => $Param{Data}->{SenderType},
    );
    my %Ticket = $TicketObject->TicketGet(
        TicketID     => $Param{Data}->{TicketID},
        Title        => $Param{Data}->{Title},
        TicketNumber => $Param{Data}->{TicketNumber},
        Queue        => $Param{Data}->{Queue},        
        State        => $Param{Data}->{State},
        OwnerID      => $Param{Data}->{OwnerID},
        Priority     => $Param{Data}->{Priority},
    );

    # system config vars
    my $TicketHook  = $ConfigObject->Get('Ticket::Hook');
       $TicketHook .= $ConfigObject->Get('Ticket::HookDivider');
    my $SystemFQDN  = $ConfigObject->Get('FQDN');
    my $SystemHTTP  = $ConfigObject->Get('HttpType');
    my $SystemAlias = $ConfigObject->Get('ScriptAlias');

    # get agent name
    $Ticket{UserName} = $UserObject->UserName( UserID => $Ticket{OwnerID} );
 
    # escape double quotes 
    (my $From_noquotes = $Article{From}) =~ s/\"/\\"/g;

    # define vars
    my $WebhookURL;
    my $MessageTitle;

    # run only for Articles with SenderType 'customer'
    if ( $Article{SenderType} ne 'customer' )
    {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Excluded running Webhook for SenderType $Article{SenderType}"
            );
        return;
    }

    if ( $Ticket{State} eq 'new' )
    { 
        $MessageTitle = "New Ticket: $Ticket{Title}"; 
        } 
    else { 
        $MessageTitle = "New message: $Article{Subject}";
        }

    # encode utf-8
    $MessageTitle = Encode::encode("utf8", $MessageTitle);
    my $Owner = Encode::encode("utf8", $Ticket{UserName});

    # get WebHookURL for Queue
    my %WebhookURLs = %{ $ConfigObject->Get( 'TeamsNotification::QueueToWebhookURL' ) };
	for my $WebHookQueue ( sort keys %WebhookURLs )   
	{
		if ( $Ticket{Queue} eq $WebHookQueue ) {
		    $WebhookURL = $WebhookURLs{$WebHookQueue};
		    $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Run WebHook for Queue $WebHookQueue"
                );
  	   }
	}

    # error on empty Webhook URL
    if ( !$WebhookURL )
    {
    	$Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No WebhookURL defined for Queue $Ticket{Queue}"
        );
        return;
    }

    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => $WebhookURL);
    $req->header('content-type' => 'application/json');

    # add POST data to HTTP request body
    my $post_data = "{
		\"\@context\": \"https://schema.org/extensions\",
		\"\@type\": \"MessageCard\",
		\"themeColor\": \"0076D7\",
        \"summary\": \"New Ticket Update\",
        \"title\": \"$MessageTitle\",
		\"sections\": [{
			\"activityTitle\": \"From: $From_noquotes\",
			\"activitySubtitle\": \"in Queue $Ticket{Queue}\",
			\"activityImage\": \"$SystemHTTP://$SystemFQDN/otrs-web/skins/Agent/default/img/none\",	
                \"facts\": [{ 
					\"name\": \"Ticket Number\", 
					\"value\": \"$TicketHook$Ticket{TicketNumber}\" 
				}, { 
					\"name\": \"Assigned to\", 
					\"value\": \"$Owner\" 
				}, { 
					\"name\": \"Status\", 
					\"value\": \"$Ticket{State}\" 
				},{ 
					\"name\": \"Priority\", 
					\"value\": \"$Ticket{Priority}\" 
				}],
                \"markdown\": true
        }],
        \"potentialAction\": [{        
					\"\@type\": \"OpenUri\", 
					\"name\": \"View in Helpdesk\",
                        \"targets\": [{ 
					        \"os\": \"default\", 
					        \"uri\": \"$SystemHTTP://$SystemFQDN/$SystemAlias/index.pl?Action=AgentTicketZoom;TicketID=$Ticket{TicketID}#$Article{ArticleID}\" 
					        }
                ]
			}
		]
	}";

    # POST
    $req->content($post_data);

    my $resp = $ua->request($req);
    if ($resp->is_success) {
      my $message = $resp->decoded_content;
      $LogObject->Log(
          Priority => 'notice',
          Message  => "Run TeamsNotification event module,Received reply: $message" ,
      );
    }
    else {
      $LogObject->Log(
        Priority => 'notice',
        Message  => "RHTTP POST error code: $resp->code" ,
      );
      $LogObject->Log(
        Priority => 'notice',
        Message  => "RHTTP POST error message: $resp->message" ,
      );
    }

    return 1;
}

1;