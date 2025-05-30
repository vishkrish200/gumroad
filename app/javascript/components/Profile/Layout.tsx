import cx from "classnames";
import * as React from "react";

import { CreatorProfile } from "$app/parsers/profile";

import { NavigationButton } from "$app/components/Button";
import { CartNavigationButton } from "$app/components/Checkout/CartNavigationButton";
import { useCartItemsCount } from "$app/components/Checkout/useCartItemsCount";
import { useDomains } from "$app/components/DomainSettings";
import { Icon } from "$app/components/Icons";
import { useLoggedInUser } from "$app/components/LoggedInUser";

import { FollowForm } from "./FollowForm";

type Props = {
  className?: string;
  creatorProfile: CreatorProfile;
  hideFollowForm?: boolean;
  children?: React.ReactNode;
};

export const Layout = ({ className, creatorProfile, hideFollowForm, children }: Props) => {
  const cartItemsCount = useCartItemsCount();
  const { rootDomain } = useDomains();
  const loggedInUser = useLoggedInUser();

  return (
    <div className={cx("profile", className)}>
      <header>
        <section>
          {(loggedInUser?.isGumroadAdmin || loggedInUser?.isImpersonating) &&
          creatorProfile.external_id !== loggedInUser.id ? (
            <NavigationButton
              style={{ position: "absolute", left: "var(--spacer-3)" }}
              color="filled"
              href={Routes.admin_impersonate_url({ user_identifier: creatorProfile.external_id })}
            >
              Impersonate
            </NavigationButton>
          ) : null}
          <img className="user-avatar" src={creatorProfile.avatar_url} alt="Profile Picture" />
          <a href={Routes.root_path()} style={{ textDecoration: "none" }}>
            {creatorProfile.name}
          </a>
        </section>
        {!hideFollowForm ? (
          <section>
            <FollowForm creatorProfile={creatorProfile} />
          </section>
        ) : null}
        {creatorProfile.twitter_handle || cartItemsCount ? (
          <section className="links">
            {creatorProfile.twitter_handle ? (
              <NavigationButton outline href={`https://twitter.com/${creatorProfile.twitter_handle}`} target="_blank">
                <Icon name="twitter" />
              </NavigationButton>
            ) : null}
            <CartNavigationButton />
          </section>
        ) : null}
      </header>
      <main className="custom-sections">
        {children}
        <footer>
          Powered by&ensp;
          <a href={Routes.root_url({ host: rootDomain })} className="logo-full" aria-label="Gumroad" />
        </footer>
      </main>
    </div>
  );
};
