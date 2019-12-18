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

    # check if Notification module should run
    my $ViewNotification = $ConfigObject->Get('TeamsNotification::NotificationView');
    if ( $ViewNotification eq 'never' ) {
        return;
    }

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
        From         => $Param{Data}->{From},
        Body         => $Param{Data}->{From},
        SenderType   => $Param{Data}->{SenderType},
    );
    my %Ticket = $TicketObject->TicketGet(
        TicketID     => $Param{Data}->{TicketID},
        Type         => $Param{Data}->{Type},
        TicketNumber => $Param{Data}->{TicketNumber},
        Title        => $Param{Data}->{Title},
        Queue        => $Param{Data}->{Queue},        
        State        => $Param{Data}->{State},
        OwnerID      => $Param{Data}->{OwnerID},
        Priority     => $Param{Data}->{Priority},
    );
    # get agent name
    $Ticket{UserName} = $UserObject->UserName( UserID => $Ticket{OwnerID} );

    # system config vars
    my $TicketHook  = $ConfigObject->Get('Ticket::Hook');
       $TicketHook .= $ConfigObject->Get('Ticket::HookDivider');
    my $SystemFQDN  = $ConfigObject->Get('FQDN');
    my $SystemHTTP  = $ConfigObject->Get('HttpType');
    my $SystemAlias = $ConfigObject->Get('ScriptAlias');
    my $WebPath     = $ConfigObject->Get('Frontend::WebPath');

    # run for defined Sender Types only
    my %SenderTypes = %{ $ConfigObject->Get( 'TeamsNotification::SenderType' ) };
	for my $SenderType ( sort keys %SenderTypes )   
	{
		if ( $SenderType eq $Article{SenderType}
             && $SenderTypes{$SenderType} == 0 ) { 
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Do not run for Sender Type $SenderType."
                );
                return;
        }    
	}

    # run for defined Ticket Types only
    my %TicketTypes = %{ $ConfigObject->Get( 'TeamsNotification::TicketType' ) };
	for my $TicketType ( sort keys %TicketTypes )   
	{
		if ( $TicketType eq $Ticket{Type}
             && $TicketTypes{$TicketType} == 0 ) { 
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Do not run for Ticket Type $TicketType."
                );
                return;
        }    
	}

    # get WebHookURL for Queue
    my $WebhookURL;
    my %WebhookURLs = %{ $ConfigObject->Get( 'TeamsNotification::QueueToWebhookURL' ) };
	for my $WebHookQueue ( sort keys %WebhookURLs )   
	{
		if ( $Ticket{Queue} eq $WebHookQueue ) {
		    $WebhookURL = $WebhookURLs{$WebHookQueue};
		    $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Run WebHook for Queue $WebHookQueue"
                );
            # error on empty Webhook URL
            if ( !$WebhookURL )
            {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "No WebhookURL defined for Queue $Ticket{Queue}"
                );
                return;
                }
  	       }
	}

    # set notification theme color
    my %Priorities = %{ $ConfigObject->Get( 'TeamsNotification::NotificationColor' ) };
    my $PriorityColor = $Priorities{default};
	for my $Priority ( sort keys %Priorities )   
	{
		if ( $Ticket{Priority} eq $Priority ) {
		    $PriorityColor = $Priorities{$Priority};
  	       }
	}

    # encode utf-8
    $Article{From} = Encode::encode("utf8", $Article{From});
    $Ticket{Title} = Encode::encode("utf8", $Ticket{Title});
    $Ticket{UserName} = Encode::encode("utf8", $Ticket{UserName});

    # escape double quotes 
    $Article{From} =~ s/\"/\\"/g;
    $Ticket{Title} =~ s/\"/\\"/g;
    $Ticket{UserName} =~ s/\"/\\"/g;

    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => $WebhookURL);
    $req->header('content-type' => 'application/json');

    # get agent logo
    my $NotificationImage = $ConfigObject->Get('TeamsNotification::NotificationImage');
    my %AgentLoginLogo = %{ $ConfigObject->Get('AgentLoginLogo') };
    my $ActivityImage;
    
    if ( $NotificationImage ) {
        $ActivityImage = "$SystemHTTP://$SystemFQDN$WebPath$NotificationImage";
    } else {
        $ActivityImage = "$SystemHTTP://$SystemFQDN$WebPath$AgentLoginLogo{URL}";
    }

    # add POST data to HTTP request body
    my $post_data_large = "{
		\"\@context\": \"https://schema.org/extensions\",
		\"\@type\": \"MessageCard\",
		\"themeColor\": \"$PriorityColor\",
        \"summary\": \"Ticket Update\",
        \"title\": \"__Ticket Update__: $Ticket{Title}\",
		\"sections\": [{
			\"activityTitle\": \"$Article{From}\",
			\"activitySubtitle\": \"$Article{SenderType}\",
			\"activityImage\": \"$ActivityImage\",	
                \"facts\": [{ 
					\"name\": \"Ticket Number\", 
					\"value\": \"$TicketHook$Ticket{TicketNumber}\" 
				}, { 
					\"name\": \"Assignee\", 
					\"value\": \"$Ticket{UserName}\" 
				}, { 
					\"name\": \"Queue\", 
					\"value\": \"$Ticket{Queue}\" 
				}, { 
					\"name\": \"Status\", 
					\"value\": \"$Ticket{State}\" 
				}, { 
					\"name\": \"Priority\", 
					\"value\": \"$Ticket{Priority}\" 
				}]
        }],
        \"markdown\" : \"true\",
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

    my $post_data_medium = "{
		\"\@context\": \"https://schema.org/extensions\",
		\"\@type\": \"MessageCard\",
		\"themeColor\": \"$PriorityColor\",
        \"summary\": \"Ticket Update\",
		\"sections\": [{
			\"activityTitle\": \"__Ticket Update__ [$TicketHook$Ticket{TicketNumber}]: $Ticket{Title}\",
			\"activitySubtitle\": \"$Article{From} ($Article{SenderType})\",
            \"activityImage\": \"$ActivityImage\",
                \"facts\": [{ 
					\"name\": \"Assignee\", 
					\"value\": \"$Ticket{UserName}\" 
				}, { 
					\"name\": \"Queue\", 
					\"value\": \"$Ticket{Queue}\" 
				}, { 
					\"name\": \"Status\", 
					\"value\": \"$Ticket{State}\" 
				}, { 
					\"name\": \"Priority\", 
					\"value\": \"$Ticket{Priority}\" 
				}]
        }],
        \"markdown\" : \"true\",
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

    my $post_data_small = "{
		\"\@context\": \"https://schema.org/extensions\",
		\"\@type\": \"MessageCard\",
		\"themeColor\": \"$PriorityColor\",
        \"summary\": \"Ticket Update\",
		\"sections\": [{
			\"activityTitle\": \"__Ticket Update__: $Ticket{Title}\",
			\"activitySubtitle\": \"$Article{From} ($Article{SenderType})\",
            \"activityImage\": \"$ActivityImage\",
            \"text\": \"New message for Ticket __$TicketHook$Ticket{TicketNumber}__ in Queue __$Ticket{Queue}__, State is __$Ticket{State}__ and Priotity is __$Ticket{Priority}__. Current Assignee is __$Ticket{UserName}__.\"
        }],
        \"markdown\" : \"true\",
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
    if ( $ViewNotification eq 'large' ) {
        $req->content($post_data_large);
        }
        elsif ( $ViewNotification eq 'medium' ) {
            $req->content($post_data_medium);
            }
            elsif ( $ViewNotification eq 'small' ) {
                $req->content($post_data_small);
                }

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